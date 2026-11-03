# Hospital Management System on AWS

## Handover summary

This repository contains an academic AWS deployment for a small hospital-management
application. It has two related demonstrations:

1. **Hospital Management System**: a static patient-appointment portal hosted by
   AWS Amplify. The browser calls a public AWS Lambda Function URL. That Lambda
   runs in private subnets in `HospitalVPC` and connects over TLS to a private
   Amazon RDS MySQL database named `HospitalDB`.
2. **Enterprise web-application scenario**: a separate EC2/EBS/Apache example
   documented in [`Q2_Scenario1_Solution.md`](./Q2_Scenario1_Solution.md). It is
   not part of the hospital portal's request path.

The primary implementation is under [`hospital/`](./hospital/). The files are
mostly PowerShell and shell scripts that provision already-designed AWS resources
using the AWS CLI. There is no conventional application framework, package
manager, or local development server.

## Architecture

```text
Browser
  |
  v
AWS Amplify Hosting (static HTML/CSS/JavaScript)
  |
  v
Lambda Function URL: HospitalPatientAPI
  |  VPC attachment, private subnets, Hospital-Lambda-SG
  v
Amazon RDS MySQL 8.x: HospitalDB
  |  private subnet, Hospital-DB-SG, port 3306 only from app/Lambda SGs
  v
PatientRecords
```

The medical-document side path is independent of the patient form:

```text
S3 bucket (private, versioned, HTTPS-only policy)
  |
  | ObjectCreated event
  v
MedicalReportProcessor Lambda
  |
  +--> validates .jpg/.jpeg/.png/.pdf/.dcm and non-empty size
  +--> writes ProcessingStatus/Detail/ProcessedBy object tags
  +--> logs successes and validation failures to CloudWatch
```

### AWS resources represented by the scripts

- `HospitalVPC` (`10.0.0.0/16`)
- Public app subnet `10.0.1.0/24`
- Private subnets `10.0.2.0/24` and `10.0.3.0/24` in two AZs
- Internet gateway and separate public/private route tables
- `Hospital-Web-SG`, `Hospital-Lambda-SG`, and `Hospital-DB-SG`
- RDS MySQL instance `hospitaldb`, database `HospitalDB`
- Private, versioned S3 bucket for diagnostic images and reports
- `MedicalReportProcessor` Lambda triggered by S3 object creation
- `HospitalPatientAPI` Lambda attached to the VPC
- Amplify app and the `main` branch for the static site
- CloudWatch dashboard configuration for the document processor

## Request and data flow

### Patient portal

[`hospital/site/index.html`](./hospital/site/index.html) defines the form and
records table. [`hospital/site/script.js`](./hospital/site/script.js) performs
client-side validation, sends `GET` and `POST` requests, escapes values before
rendering table rows, and refreshes the records view.

The API Lambda in
[`hospital/lambda_api/lambda_function.py`](./hospital/lambda_api/lambda_function.py)
does the server-side validation and database work:

- `GET`: returns the newest 25 records and the total count.
- `POST`: accepts a JSON patient record, validates the ID/name/department/date,
  inserts it with parameterized SQL, and reports duplicate IDs as HTTP 409.
- The database connection uses the RDS CA bundle and TLS.
- The intended database user is least privilege: CRUD only on
  `HospitalDB.PatientRecords`.

The deploy script copies `site/` to `dist/`, replaces `__API_URL__` in the
JavaScript with the deployed Lambda Function URL, zips the static files, and
uploads the ZIP through the Amplify deployment API.

### Medical documents

[`hospital/lambda_processor/lambda_function.py`](./hospital/lambda_processor/lambda_function.py)
handles S3 events. It URL-decodes keys, validates the extension and object size,
checks object metadata with `head_object`, tags the object, and logs a structured
success message. Unsupported extensions and empty files are intentionally raised
as errors so they appear in the Lambda error metric.

## Repository map

| Path | Purpose |
|---|---|
| [`hospital/01_vpc.ps1`](./hospital/01_vpc.ps1) | Creates VPC, subnets, routes, IGW, security groups, and initial `state.json`. |
| [`hospital/02_rds.ps1`](./hospital/02_rds.ps1) | Creates the RDS subnet group and encrypted, non-public MySQL instance. Generates a password file locally. |
| [`hospital/03_s3.ps1`](./hospital/03_s3.ps1) | Creates the private/versioned bucket, HTTPS-only policy, and sample objects. |
| [`hospital/04_lambda.ps1`](./hospital/04_lambda.ps1) | Creates the document-processing role/function and S3 notification. |
| [`hospital/05_api.ps1`](./hospital/05_api.ps1) | Creates the VPC-connected patient API Lambda and public Function URL. |
| [`hospital/06_amplify_deploy.ps1`](./hospital/06_amplify_deploy.ps1) | Injects the API URL into the frontend and deploys to Amplify. |
| [`hospital/99_cleanup.ps1`](./hospital/99_cleanup.ps1) | Deletes the provisioned AWS resources. Destructive: run only after the demo. |
| [`hospital/db_setup.template.sh`](./hospital/db_setup.template.sh) | Intended EC2-side SQL/bootstrap template for `PatientRecords` and `hospital_app`. |
| [`hospital/lambda_api/`](./hospital/lambda_api/) | Source for the patient API Lambda. |
| [`hospital/lambda_processor/`](./hospital/lambda_processor/) | Source for the S3 medical-document Lambda. |
| [`hospital/site/`](./hospital/site/) | Source static frontend. |
| [`hospital/dashboard.json`](./hospital/dashboard.json) | CloudWatch dashboard definition for processor invocations, errors, duration, and logs. |
| [`hospital/DEMO_GUIDE.md`](./hospital/DEMO_GUIDE.md) | Existing examiner/demo walkthrough with AWS Console links and screenshots to collect. |
| [`Q2_Scenario1_Solution.md`](./Q2_Scenario1_Solution.md) | Separate EC2/EBS/Apache enterprise scenario instructions. |
| [`hospital/make_files.py`](./hospital/make_files.py) | Generates synthetic PDF test documents and intentionally invalid test files. |
| [`hospital/make_scan.ps1`](./hospital/make_scan.ps1) | Generates a synthetic X-ray-style JPEG for the S3 demo. |

## Intended deployment order

### Prerequisites

- Windows PowerShell and AWS CLI v2.
- An authenticated AWS CLI identity with permissions for VPC, EC2, RDS, S3,
  Lambda, IAM, CloudWatch, and Amplify.
- A selected AWS region. The current scripts and demo guide assume
  `us-east-1`.
- The AWS CLI path is hard-coded as
  `%LOCALAPPDATA%\Programs\Amazon\AWSCLIV2\aws.exe`; adjust it if AWS CLI is
  installed elsewhere.
- The scripts use an absolute project path in several places. Replace the
  `D:\AA sem 7\Cloud_endsem\hospital` values when moving the project.

### Provisioning sequence

Run each script from the `hospital` directory and stop on errors:

```powershell
.\01_vpc.ps1
.\02_rds.ps1
.\03_s3.ps1
.\04_lambda.ps1
.\05_api.ps1
.\06_amplify_deploy.ps1
```

RDS and IAM creation are asynchronous. Wait for the database to become
available and allow IAM policy propagation before invoking dependent steps.
The scripts persist resource IDs in `state.json`; this is runtime state, not a
portable infrastructure state format.

After RDS is reachable, the intended next operation is to render
`db_setup.template.sh` with the RDS endpoint and credentials, run it on the app
server, and then package/deploy the API Lambda with the same application
credentials. The repository does not currently contain a complete, automated
render-and-upload step for that bootstrap.

### Demo sequence

1. Open the Amplify site and submit a valid future appointment.
2. Refresh the records list and verify the row came from RDS.
3. Upload a valid PDF/JPEG to the S3 bucket and inspect Lambda logs/tags.
4. Upload `empty-report.pdf` or `corrupted-upload.exe` to demonstrate rejected
   objects and CloudWatch errors.
5. Show the private bucket policy, RDS non-public setting, VPC resource map,
   security-group rules, and CloudWatch dashboard.
6. Use [`hospital/DEMO_GUIDE.md`](./hospital/DEMO_GUIDE.md) for the detailed
   console links and examiner narration.

### Cleanup

When the demo is finished, review the IDs in `state.json` and run:

```powershell
.\99_cleanup.ps1
```

This removes live cloud resources, including the RDS instance and all S3 object
versions. Verify the AWS account manually afterward because cleanup is
best-effort and the script intentionally suppresses many individual CLI errors.

## Important handover findings

These are the first items another AI should resolve before attempting a fresh
deployment:

1. **Credential safety**: local files such as `db-secret.json` and
   `cli-admin_accessKeys.csv` contain sensitive values and must never be
   committed. They are excluded by `.gitignore`. If either credential was real,
   rotate/revoke it before sharing the repository.
2. **Generated artifacts**: `build_api/`, ZIP files, `dist/`, `state.json`,
   `out.json`, and generated sample documents are deployment outputs or local
   state, not the source of truth. Rebuild them from source where possible.
3. **RDS/API configuration mismatch**: `02_rds.ps1` writes administrator fields
   to `db-secret.json`, while `05_api.ps1` expects `endpoint`, `appUser`, and
   `appPassword`. A fresh run therefore needs an explicit step that creates the
   least-privilege user, obtains the RDS endpoint, and supplies those values
   before the API Lambda can connect.
4. **API package provenance**: `05_api.ps1` uploads the prebuilt
   `lambda_api.zip`. Rebuild it from `lambda_api/` plus the pinned runtime
   dependency before deploying to avoid shipping stale code.
5. **Existing state is environment-specific**: the checked-out local state may
   refer to an already-created AWS account, region, bucket, Amplify app, and
   Lambda URL. Do not assume those resources exist or are safe to reuse.
6. **Public API URL**: the Function URL is configured with unauthenticated
   access for the classroom demo. A production version needs authentication,
   throttling, input/rate controls, and a safer secret-management approach
   such as Secrets Manager.
7. **Medical data is synthetic**: files under `hospital/files/` are demo
   fixtures. Do not replace them with real patient information.

## Local validation and development

There is no automated test suite in the current project. Before changing
deployment code:

- Use Python syntax checking for the two Lambda source files.
- Validate JSON files with a JSON parser.
- Inspect the generated frontend after API URL injection.
- Run AWS CLI `describe`/`get` commands against a disposable account or
  sandbox before using the cleanup script.
- Test both successful and rejected S3 uploads and duplicate patient IDs.

The frontend can be previewed as static files, but it will not load records
until `__API_URL__` is replaced with a reachable API Function URL and that URL's
CORS configuration allows the frontend origin.

## Security notes

- Do not commit access keys, database passwords, API environment files, generated
  deployment packages, or runtime resource state.
- Keep RDS private and restrict port 3306 to the application security groups.
- Keep the S3 public-access block enabled and require TLS.
- Rotate any credentials that have appeared in local files or screenshots.
- Treat the existing demo URLs and AWS resource IDs as stale until verified in
  the target account.

