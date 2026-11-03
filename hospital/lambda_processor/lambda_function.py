"""MedicalReportProcessor - triggered by S3 ObjectCreated events.

Logs the uploaded file name + bucket, validates the document and tags it
with its processing status. Invalid uploads raise an error so they show up
in the CloudWatch Errors metric.
"""
import json
import logging
import os
import time
import urllib.parse

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)
s3 = boto3.client("s3")

ALLOWED = {".jpg": "Diagnostic Image", ".jpeg": "Diagnostic Image", ".png": "Diagnostic Image",
           ".pdf": "Medical Report", ".dcm": "DICOM Scan"}


def lambda_handler(event, context):
    records = event.get("Records", [])
    logger.info("Received S3 event with %d record(s)", len(records))
    results = []

    for rec in records:
        start = time.time()
        bucket = rec["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(rec["s3"]["object"]["key"])
        size = rec["s3"]["object"].get("size", 0)
        file_name = os.path.basename(key)
        ext = os.path.splitext(file_name)[1].lower()

        logger.info("NEW FILE UPLOADED | file_name=%s | bucket=%s | key=%s | size=%s bytes | event=%s | time=%s",
                    file_name, bucket, key, size, rec.get("eventName"), rec.get("eventTime"))

        if ext not in ALLOWED:
            logger.error("VALIDATION FAILED | file_name=%s | reason=Unsupported file type '%s'", file_name, ext)
            tag(bucket, key, "REJECTED", "unsupported-type")
            raise ValueError(f"Unsupported file type for {file_name}")
        if size == 0:
            logger.error("VALIDATION FAILED | file_name=%s | reason=Empty document (0 bytes)", file_name)
            tag(bucket, key, "REJECTED", "empty-file")
            raise ValueError(f"Empty document {file_name}")

        head = s3.head_object(Bucket=bucket, Key=key)
        doc_type = ALLOWED[ext]
        tag(bucket, key, "PROCESSED", doc_type.replace(" ", "-"))
        elapsed = round((time.time() - start) * 1000, 1)
        logger.info("PROCESSED OK | file_name=%s | document_type=%s | content_type=%s | took=%sms",
                    file_name, doc_type, head.get("ContentType"), elapsed)
        results.append({"file": file_name, "bucket": bucket, "type": doc_type, "status": "PROCESSED"})

    return {"statusCode": 200, "body": json.dumps(results)}


def tag(bucket, key, status, detail):
    try:
        s3.put_object_tagging(Bucket=bucket, Key=key, Tagging={"TagSet": [
            {"Key": "ProcessingStatus", "Value": status},
            {"Key": "Detail", "Value": detail},
            {"Key": "ProcessedBy", "Value": "MedicalReportProcessor"}]})
    except Exception as exc:  # tagging is best effort
        logger.warning("Could not tag %s: %s", key, exc)
