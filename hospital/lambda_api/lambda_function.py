"""HospitalPatientAPI - backend for the Amplify patient form.

Runs inside HospitalVPC (private subnet) and is one of the only two resources
allowed to reach RDS (security group Hospital-DB-SG). Connects over TLS as the
least-privilege user hospital_app.

GET  -> latest patient records
POST -> insert a new patient record (JSON body)
"""
import datetime
import json
import logging
import os
import re

import pymysql

logger = logging.getLogger()
logger.setLevel(logging.INFO)

CA = os.path.join(os.path.dirname(__file__), "rds-ca.pem")
DEPARTMENTS = {"Cardiology", "Neurology", "Orthopedics", "Pediatrics", "Radiology", "Pathology",
               "Dermatology", "General Medicine", "ENT", "Oncology", "Gynecology", "Emergency",
               "Cardiothoracic Surgery"}
_conn = None


def db():
    global _conn
    if _conn is None or not _conn.open:
        _conn = pymysql.connect(host=os.environ["DB_HOST"], user=os.environ["DB_USER"],
                                password=os.environ["DB_PASS"], database=os.environ["DB_NAME"],
                                ssl={"ca": CA}, connect_timeout=5, autocommit=True,
                                cursorclass=pymysql.cursors.DictCursor)
    else:
        _conn.ping(reconnect=True)
    return _conn


def resp(code, body):
    return {"statusCode": code, "headers": {"Content-Type": "application/json"},
            "body": json.dumps(body, default=str)}


def lambda_handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    try:
        if method == "GET":
            with db().cursor() as cur:
                cur.execute("SELECT PatientID, PatientName, Department, AppointmentDate, CreatedAt "
                            "FROM PatientRecords ORDER BY CreatedAt DESC, PatientID LIMIT 25")
                rows = cur.fetchall()
                cur.execute("SELECT COUNT(*) AS total FROM PatientRecords")
                total = cur.fetchone()["total"]
            return resp(200, {"total": total, "records": rows})

        if method == "POST":
            body = json.loads(event.get("body") or "{}")
            pid = str(body.get("patientId", "")).strip().upper()
            name = str(body.get("patientName", "")).strip()
            dept = str(body.get("department", "")).strip()
            date = str(body.get("appointmentDate", "")).strip()

            errors = []
            if not re.fullmatch(r"P\d{3,8}", pid):
                errors.append("Patient ID must look like P1001")
            if not re.fullmatch(r"[A-Za-z][A-Za-z .'-]{1,99}", name):
                errors.append("Patient name must contain letters only (2-100 chars)")
            if dept not in DEPARTMENTS:
                errors.append("Unknown department")
            try:
                datetime.date.fromisoformat(date)
            except ValueError:
                errors.append("Appointment date must be YYYY-MM-DD")
            if errors:
                return resp(400, {"ok": False, "errors": errors})

            try:
                with db().cursor() as cur:
                    cur.execute("INSERT INTO PatientRecords (PatientID, PatientName, Department, AppointmentDate) "
                                "VALUES (%s, %s, %s, %s)", (pid, name, dept, date))
            except pymysql.err.IntegrityError:
                return resp(409, {"ok": False, "errors": [f"Patient ID {pid} already exists"]})
            logger.info("Inserted patient %s (%s) into HospitalDB.PatientRecords", pid, dept)
            return resp(201, {"ok": True, "message": f"Patient {pid} saved to Amazon RDS (HospitalDB)"})

        return resp(405, {"ok": False, "errors": ["Method not allowed"]})
    except Exception as exc:
        logger.exception("API failure")
        return resp(500, {"ok": False, "errors": ["Server error: " + type(exc).__name__]})
