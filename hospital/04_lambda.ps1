$ErrorActionPreference = "Stop"
$aws = "$env:LOCALAPPDATA\Programs\Amazon\AWSCLIV2\aws.exe"
$dir = "D:\AA sem 7\Cloud_endsem\hospital"
$s = Get-Content "$dir\state.json" | ConvertFrom-Json
$acct = & $aws sts get-caller-identity --query Account --output text
$bucket = $s.bucket
function fileurl($p) { "file://" + ($p -replace '\\','/') }

# IAM role
'{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' | Out-File -Encoding ascii "$dir\lambda-trust.json"
$roleArn = & $aws iam create-role --role-name MedicalReportProcessorRole --assume-role-policy-document (fileurl "$dir\lambda-trust.json") --tags Key=Project,Value=HospitalMS --query Role.Arn --output text
& $aws iam attach-role-policy --role-name MedicalReportProcessorRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
@"
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:GetObjectTagging","s3:PutObjectTagging"],"Resource":"arn:aws:s3:::$bucket/*"}]}
"@ | Out-File -Encoding ascii "$dir\lambda-s3-policy.json"
& $aws iam put-role-policy --role-name MedicalReportProcessorRole --policy-name MedicalBucketAccess --policy-document (fileurl "$dir\lambda-s3-policy.json")
Start-Sleep -Seconds 12   # IAM propagation

# Package + create function
$zip = "$dir\lambda_processor.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path "$dir\lambda_processor\lambda_function.py" -DestinationPath $zip
& $aws lambda create-function --function-name MedicalReportProcessor --runtime python3.12 --architectures x86_64 `
  --role $roleArn --handler lambda_function.lambda_handler --zip-file (("fileb://" + ($zip -replace '\\','/'))) `
  --timeout 30 --memory-size 128 --description "Processes medical documents uploaded to S3 and logs file name + bucket" `
  --tags Project=HospitalMS --query '[FunctionName,State]' --output text
& $aws lambda wait function-active-v2 --function-name MedicalReportProcessor
& $aws logs create-log-group --log-group-name /aws/lambda/MedicalReportProcessor 2>$null
& $aws logs put-retention-policy --log-group-name /aws/lambda/MedicalReportProcessor --retention-in-days 7

# Allow S3 to invoke it, then configure the ObjectCreated trigger
& $aws lambda add-permission --function-name MedicalReportProcessor --statement-id s3-invoke-medical-bucket `
  --action lambda:InvokeFunction --principal s3.amazonaws.com --source-arn "arn:aws:s3:::$bucket" --source-account $acct | Out-Null
$fnArn = & $aws lambda get-function --function-name MedicalReportProcessor --query Configuration.FunctionArn --output text
@"
{"LambdaFunctionConfigurations":[{"Id":"MedicalReportUploadTrigger","LambdaFunctionArn":"$fnArn","Events":["s3:ObjectCreated:*"]}]}
"@ | Out-File -Encoding ascii "$dir\s3-notification.json"
& $aws s3api put-bucket-notification-configuration --bucket $bucket --notification-configuration (fileurl "$dir\s3-notification.json")
& $aws s3api get-bucket-notification-configuration --bucket $bucket --output json
