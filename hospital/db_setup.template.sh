#!/bin/bash
# One-time DB setup on Hospital-App-Server. Placeholders are filled in by PowerShell before upload.
set -e
ENDPOINT="__ENDPOINT__"
cd /home/ec2-user

# Amazon RDS CA bundle -> verified TLS connections
curl -s -o rds-ca.pem https://truststore.pki.rds.amazonaws.com/us-east-1/us-east-1-bundle.pem

# Temporary admin config (deleted at the end)
cat > /tmp/admin.cnf <<EOF
[client]
host=$ENDPOINT
user=admin
password=__ADMINPW__
ssl-ca=/home/ec2-user/rds-ca.pem
ssl-verify-server-cert
EOF
chmod 600 /tmp/admin.cnf

mysql --defaults-extra-file=/tmp/admin.cnf HospitalDB <<'SQL'
CREATE TABLE IF NOT EXISTS PatientRecords (
  PatientID        VARCHAR(10)  NOT NULL PRIMARY KEY,
  PatientName      VARCHAR(100) NOT NULL,
  Department       VARCHAR(50)  NOT NULL,
  AppointmentDate  DATE         NOT NULL,
  CreatedAt        TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);
DROP USER IF EXISTS 'hospital_app'@'10.0.%';
CREATE USER 'hospital_app'@'10.0.%' IDENTIFIED BY '__APPPW__' REQUIRE SSL;
GRANT SELECT, INSERT, UPDATE, DELETE ON HospitalDB.PatientRecords TO 'hospital_app'@'10.0.%';
FLUSH PRIVILEGES;
SQL
rm -f /tmp/admin.cnf

# Everyday (least-privilege) login used for the demo
cat > /home/ec2-user/.my.cnf <<EOF
[client]
host=$ENDPOINT
user=hospital_app
password=__APPPW__
database=HospitalDB
ssl-ca=/home/ec2-user/rds-ca.pem
ssl-verify-server-cert
EOF
chmod 600 /home/ec2-user/.my.cnf

mkdir -p /home/ec2-user/hospital-sql
cd /home/ec2-user/hospital-sql

cat > 01_describe_table.sql <<'SQL'
SHOW TABLES;
DESCRIBE PatientRecords;
SQL

cat > 02_insert.sql <<'SQL'
INSERT INTO PatientRecords (PatientID, PatientName, Department, AppointmentDate) VALUES
  ('P1001', 'Arjun Menon',  'Radiology',   '2026-10-21'),
  ('P1002', 'Priya Sharma', 'Pathology',   '2026-10-22'),
  ('P1003', 'Rahul Verma',  'Cardiology',  '2026-10-23'),
  ('P1004', 'Sneha Iyer',   'Neurology',   '2026-10-24'),
  ('P1005', 'Vikram Rao',   'Orthopedics', '2026-10-25');
SQL

cat > 03_select.sql <<'SQL'
SELECT PatientID, PatientName, Department, AppointmentDate FROM PatientRecords ORDER BY PatientID;
SELECT * FROM PatientRecords WHERE Department = 'Cardiology';
SQL

cat > 04_update.sql <<'SQL'
UPDATE PatientRecords SET Department = 'Cardiothoracic Surgery', AppointmentDate = '2026-10-30' WHERE PatientID = 'P1003';
SELECT PatientID, PatientName, Department, AppointmentDate FROM PatientRecords WHERE PatientID = 'P1003';
SQL

cat > 05_delete.sql <<'SQL'
DELETE FROM PatientRecords WHERE PatientID = 'P1005';
SELECT PatientID, PatientName, Department, AppointmentDate FROM PatientRecords ORDER BY PatientID;
SQL

cat > run-demo.sh <<'EOS'
#!/bin/bash
# Runs the full CRUD demo against RDS HospitalDB (secure SSL login as least-privilege user)
step() { echo; echo "=================================================================="; echo ">>> $1"; echo "=================================================================="; }
mysql -e "DELETE FROM PatientRecords WHERE PatientID IN ('P1001','P1002','P1003','P1004','P1005');" >/dev/null 2>&1

step "Connected securely (SSL) to RDS MySQL as least-privilege user"
mysql -t -e "SELECT CURRENT_USER() AS logged_in_as, DATABASE() AS db, @@hostname AS rds_host, @@version AS mysql_version; SHOW SESSION STATUS LIKE 'Ssl_cipher';"
step "TABLE: PatientRecords structure";               mysql -t < 01_describe_table.sql
step "INSERT 5 sample patient records";               cat 02_insert.sql; mysql -t < 02_insert.sql; echo "-> 5 rows inserted"
step "SELECT all records + filter by department";     mysql -t < 03_select.sql
step "UPDATE patient P1003 (department + date)";      mysql -t < 04_update.sql
step "DELETE patient P1005, then SELECT remaining";   mysql -t < 05_delete.sql
echo; echo "Demo complete."
EOS
chmod +x run-demo.sh
chown -R ec2-user:ec2-user /home/ec2-user/hospital-sql /home/ec2-user/.my.cnf /home/ec2-user/rds-ca.pem
echo "SETUP OK"
