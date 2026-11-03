# Hospital Management System on AWS – Demo Guide

Before you start: log in to the AWS Console (account **937083180364**) and make sure the region (top-right) is **N. Virginia (us-east-1)**.
Every link below opens the right page directly.

**Live website (anyone can open it on their phone/laptop):**
👉 https://main.d2vzxkjv0kkchl.amplifyapp.com

---

## Quick links + screenshot checklist

| Q | Open | Screenshot |
|---|---|---|
| Q1 | [Live website](https://main.d2vzxkjv0kkchl.amplifyapp.com) | Form + records table (after submitting a patient) |
| Q1 | [Amplify deployments](https://us-east-1.console.aws.amazon.com/amplify/apps/d2vzxkjv0kkchl/branches/main/deployments) | Deployment *Succeeded* + domain URL |
| Q2 | [RDS HospitalDB](https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#database:id=hospitaldb;is-cluster=false) | Status Available, Connectivity tab (*Publicly accessible: No*), Configuration tab (*DB name HospitalDB*) |
| Q2 | [Connect to App Server](https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#ConnectToInstance:instanceId=i-0489a7397fded5bcf) → EC2 Instance Connect → Connect → `cd hospital-sql && ./run-demo.sh` | Terminal output of INSERT / SELECT / UPDATE / DELETE |
| Q3 | [S3 objects](https://us-east-1.console.aws.amazon.com/s3/buckets/hospital-medical-records-937083180364?region=us-east-1&tab=objects) | Both folders / files listed |
| Q3 | [S3 permissions](https://us-east-1.console.aws.amazon.com/s3/buckets/hospital-medical-records-937083180364?region=us-east-1&tab=permissions) | *Block all public access: On* + bucket policy |
| Q3 | [scan.jpg details](https://us-east-1.console.aws.amazon.com/s3/object/hospital-medical-records-937083180364?region=us-east-1&prefix=diagnostic-images/scan.jpg) · [medical-report.pdf details](https://us-east-1.console.aws.amazon.com/s3/object/hospital-medical-records-937083180364?region=us-east-1&prefix=medical-reports/medical-report.pdf) | Object overview |
| Q3 | [Public URL of scan.jpg](https://hospital-medical-records-937083180364.s3.amazonaws.com/diagnostic-images/scan.jpg) | **AccessDenied** page = public access restricted |
| Q4 | [Lambda code](https://us-east-1.console.aws.amazon.com/lambda/home?region=us-east-1#/functions/MedicalReportProcessor?tab=code) | Diagram with S3 trigger + Python code |
| Q4 | [S3 event notification](https://us-east-1.console.aws.amazon.com/s3/buckets/hospital-medical-records-937083180364?region=us-east-1&tab=properties) (scroll to *Event notifications*) | ObjectCreated → MedicalReportProcessor |
| Q4 | [Lambda log group](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/$252Faws$252Flambda$252FMedicalReportProcessor) → newest stream | `NEW FILE UPLOADED \| file_name=… \| bucket=…` lines |
| Q5 | [HospitalVPC](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#VpcDetails:VpcId=vpc-0d966d5c8021e9823) → **Resource map** tab | Full map: subnets, route tables, IGW |
| Q5 | [Subnets](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#subnets:vpcId=vpc-0d966d5c8021e9823) · [Route tables](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#RouteTables:vpcId=vpc-0d966d5c8021e9823) · [Internet Gateway](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#InternetGateway:internetGatewayId=igw-034447d58864a576d) | CIDRs, routes, *Attached* |
| Q5 | [DB security group](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#SecurityGroup:groupId=sg-00bb21842b5474e3d) · [Web security group](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#SecurityGroup:groupId=sg-0fcaedd09a8defc68) | Inbound rules tab |
| Q6 | [HospitalMonitoringDashboard](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards/dashboard/HospitalMonitoringDashboard?start=PT1H) | Whole dashboard (graphs + error log table) |
| Q6 | [Lambda Monitor tab](https://us-east-1.console.aws.amazon.com/lambda/home?region=us-east-1#/functions/MedicalReportProcessor?tab=monitoring) | Built-in metrics (backup view) |

---

## Q1 – Webpage on AWS Amplify

1. Open the **website** link above. Point out: Patient ID, Patient Name, Department, Appointment Date, **Submit** and **Reset**.
2. Live demo: fill in a new patient (e.g. `P1007`, your friend's name, *Cardiology*, a future date) → **Submit** → green message + the row appears in *Patient Records* on the right.
3. Show validation: click **Submit** with empty fields → red error messages. Click **Reset** → form clears.
4. Show it in the console: [Amplify app](https://us-east-1.console.aws.amazon.com/amplify/apps/d2vzxkjv0kkchl/overview) → branch **main** → *Deployment status: Deployed* and the published URL.

**What to say:** "The page is HTML + CSS + JavaScript, hosted on AWS Amplify. The form is connected to the database through a Lambda API inside our VPC."

---

## Q2 – Amazon RDS MySQL `HospitalDB`

1. [RDS database page](https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#database:id=hospitaldb) → show *Status: Available*, *Engine: MySQL 8.4*, **Connectivity & security** tab → *Publicly accessible: No*, VPC = HospitalVPC, security group = Hospital-DB-SG. **Configuration** tab → *DB name: HospitalDB*, *Encryption: Enabled*.
2. Run the queries live:
   [EC2 Instances](https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#Instances:tag:Name=Hospital-App-Server) → select **Hospital-App-Server** → **Connect** → tab *EC2 Instance Connect* → **Connect**. In the black terminal type:
   ```bash
   cd hospital-sql
   ./run-demo.sh
   ```
   It shows, step by step: secure SSL login → table structure → **INSERT** 5 patients → **SELECT** → **UPDATE** P1003 → **DELETE** P1005.
3. Show the website data is in the same database:
   ```bash
   mysql -t -e "SELECT * FROM PatientRecords;"
   ```
   The patient your friend submitted on the website appears here.
4. Individual query files (if the examiner asks): `cat 02_insert.sql`, `cat 04_update.sql` etc.

**Secure access – what to say:**
- The database is in a **private subnet**, *Publicly accessible = No* (no internet route).
- Only two resources may connect on port 3306: the App Server and the API Lambda (security group rule).
- Connections are encrypted with **SSL/TLS** (cipher `TLS_AES_256_GCM_SHA384` shown in the demo).
- Day-to-day queries use a **least-privilege user** `hospital_app` that can only SELECT/INSERT/UPDATE/DELETE on `PatientRecords`, and only from inside the VPC (`10.0.%`). Storage is encrypted.

---

## Q3 – S3 bucket for diagnostic images & reports

1. [S3 bucket](https://us-east-1.console.aws.amazon.com/s3/buckets/hospital-medical-records-937083180364?region=us-east-1) → folders `diagnostic-images/scan.jpg` and `medical-reports/medical-report.pdf`.
2. **Permissions** tab → *Block all public access: **On***. Bucket policy denies any non-HTTPS access.
3. Proof of restricted access: click `scan.jpg` → copy **Object URL** → paste in a new browser tab → **AccessDenied** (XML error).
   Then click the **Open** button on the same page → the X-ray image opens (authorized, temporary signed link).
4. Bonus: **Properties** → *Bucket Versioning: Enabled*.

---

## Q4 – Lambda `MedicalReportProcessor` + S3 trigger

1. [Lambda function](https://us-east-1.console.aws.amazon.com/lambda/home?region=us-east-1#/functions/MedicalReportProcessor) → the diagram shows **S3** as trigger (event: *All object create events*). Show the **Code** tab (Python).
2. Live demo: go back to the S3 bucket → **Upload** → pick any `.pdf` or `.jpg` from `D:\AA sem 7\Cloud_endsem\hospital\files` → Upload.
3. Open the [CloudWatch log group](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/$252Faws$252Flambda$252FMedicalReportProcessor) → newest log stream → you'll see:
   `NEW FILE UPLOADED | file_name=... | bucket=hospital-medical-records-937083180364 ...` and `PROCESSED OK`.
4. Bonus: click the uploaded file in S3 → **Tags** → `ProcessingStatus = PROCESSED` (the Lambda tagged it automatically).

---

## Q5 – VPC `HospitalVPC` (10.0.0.0/16)

1. [HospitalVPC](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#vpcs:VpcId=vpc-0d966d5c8021e9823) → select it → **Resource map** tab. This picture shows everything at once: subnets → route tables → Internet Gateway.
2. Explain:
   | Resource | Detail |
   |---|---|
   | Hospital-Public-Subnet | 10.0.1.0/24 – App Server, route `0.0.0.0/0 → Hospital-IGW` |
   | Hospital-Private-Subnet | 10.0.2.0/24 – RDS + API Lambda, **no internet route** |
   | Hospital-IGW | Internet Gateway attached to HospitalVPC |
   | Hospital-Public-RT / Hospital-Private-RT | public has IGW route, private only `local` |
3. [Security groups](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#SecurityGroups:vpc-id=vpc-0d966d5c8021e9823):
   - **Hospital-Web-SG**: HTTP 80 / HTTPS 443 from anywhere (web traffic), SSH 22 only from admin IPs + EC2 Instance Connect.
   - **Hospital-DB-SG**: MySQL 3306 **only from Hospital-Web-SG and Hospital-Lambda-SG** – no IP ranges at all → only authorized app resources.
4. Optional: open `http://44.214.44.147` (EC2 → Hospital-App-Server → *Public IPv4*) → "Hospital App Server" page = web traffic allowed.
   ⚠️ Your college Wi-Fi blocks plain `http://` sites, so open this one on **mobile data** (phone hotspot). The Amplify website is `https://` and works everywhere.

**If asked about the third subnet** (`Hospital-Private-Subnet-DB-Standby`, us-east-1b): AWS requires an RDS *DB subnet group* to cover at least two Availability Zones. The database itself runs only in the private subnet in us-east-1a.

---

## Q6 – CloudWatch dashboard `HospitalMonitoringDashboard`

1. [Dashboard](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards/dashboard/HospitalMonitoringDashboard) → graphs: **Invocations**, **Errors**, **Duration** (avg/max/min), totals + success %, and two log tables.
2. Point at the **Errors** spike: we uploaded `corrupted-upload.exe` (wrong type) and `empty-report.pdf` (0 bytes) – the processor rejects them.
   (Each bad file shows up to 3 errors: S3 invokes Lambda asynchronously and AWS retries a failed run twice.)
3. Bottom table *"Execution logs – errors & rejected uploads"* shows the exact error lines: `VALIDATION FAILED | file_name=corrupted-upload.exe | reason=Unsupported file type '.exe'`.
4. Live demo: upload a few more reports in S3 → wait 1–2 minutes → click the refresh ↻ button on the dashboard → Invocations goes up.
   Set the time range (top right) to **1h** for the clearest graphs.

---

## Architecture (one line)

`User → AWS Amplify (website) → Lambda HospitalPatientAPI (private subnet) → RDS MySQL HospitalDB`
`Staff upload → S3 bucket → Lambda MedicalReportProcessor → CloudWatch Logs/Metrics → HospitalMonitoringDashboard`
All inside **HospitalVPC** with security groups allowing web traffic but restricting the database to the app resources.

## When the demo is over
Tell Claude "clean up" – it runs `99_cleanup.ps1`, which deletes every resource above.
