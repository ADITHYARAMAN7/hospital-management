$ErrorActionPreference = "Stop"
$aws = "$env:LOCALAPPDATA\Programs\Amazon\AWSCLIV2\aws.exe"
$dir = "D:\AA sem 7\Cloud_endsem\hospital"
$s = Get-Content "$dir\state.json" | ConvertFrom-Json
$sec = Get-Content "$dir\db-secret.json" | ConvertFrom-Json
function fileurl($p) { "file://" + ($p -replace '\\','/') }

$roleArn = & $aws iam create-role --role-name HospitalPatientAPIRole --assume-role-policy-document (fileurl "$dir\lambda-trust.json") --tags Key=Project,Value=HospitalMS --query Role.Arn --output text
& $aws iam attach-role-policy --role-name HospitalPatientAPIRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole
Start-Sleep -Seconds 12

@{ Variables = @{ DB_HOST = $sec.endpoint; DB_USER = $sec.appUser; DB_PASS = $sec.appPassword; DB_NAME = "HospitalDB" } } |
  ConvertTo-Json | Out-File -Encoding ascii "$dir\api-env.json"

& $aws lambda create-function --function-name HospitalPatientAPI --runtime python3.12 --role $roleArn `
  --handler lambda_function.lambda_handler --zip-file ("fileb://" + ("$dir\lambda_api.zip" -replace '\\','/')) `
  --timeout 15 --memory-size 256 --description "Patient form API (Amplify -> Lambda -> RDS HospitalDB) inside HospitalVPC" `
  --vpc-config "SubnetIds=$($s.privSubnet),$($s.privSubnet2),SecurityGroupIds=$($s.lambdaSg)" `
  --environment (fileurl "$dir\api-env.json") --tags Project=HospitalMS --query '[FunctionName,State]' --output text
Remove-Item "$dir\api-env.json"
& $aws lambda wait function-active-v2 --function-name HospitalPatientAPI

$cors = "AllowOrigins=$($s.amplifyUrl),AllowMethods=GET,POST,AllowHeaders=content-type,MaxAge=300"
$url = & $aws lambda create-function-url-config --function-name HospitalPatientAPI --auth-type NONE --cors $cors --query FunctionUrl --output text
& $aws lambda add-permission --function-name HospitalPatientAPI --statement-id public-url-invoke --action lambda:InvokeFunctionUrl --principal "*" --function-url-auth-type NONE | Out-Null
$s | Add-Member -NotePropertyName apiUrl -NotePropertyValue $url -Force
$s | ConvertTo-Json | Out-File -Encoding utf8 "$dir\state.json"
$url
