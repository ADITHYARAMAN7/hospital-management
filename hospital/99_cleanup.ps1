# Deletes every Hospital Management System resource. Run only after the demo.
$aws = "$env:LOCALAPPDATA\Programs\Amazon\AWSCLIV2\aws.exe"
$dir = "D:\AA sem 7\Cloud_endsem\hospital"
$s = Get-Content "$dir\state.json" | ConvertFrom-Json
function q { param([Parameter(ValueFromRemainingArguments)]$a) & $aws @a 2>&1 | Out-Null }

"Amplify app";  q amplify delete-app --app-id $s.amplifyAppId
"Lambdas";      q lambda delete-function --function-name HospitalPatientAPI; q lambda delete-function --function-name MedicalReportProcessor
q logs delete-log-group --log-group-name /aws/lambda/HospitalPatientAPI; q logs delete-log-group --log-group-name /aws/lambda/MedicalReportProcessor
"Dashboard";    q cloudwatch delete-dashboards --dashboard-names HospitalMonitoringDashboard

"S3 bucket (all versions)"
q s3api put-bucket-notification-configuration --bucket $s.bucket --notification-configuration "{}"
do {
  $v = & $aws s3api list-object-versions --bucket $s.bucket --max-items 900 --output json | ConvertFrom-Json
  $objs = @($v.Versions) + @($v.DeleteMarkers) | Where-Object { $_ } | ForEach-Object { @{ Key = $_.Key; VersionId = $_.VersionId } }
  if ($objs.Count -gt 0) {
    @{ Objects = $objs; Quiet = $true } | ConvertTo-Json -Depth 4 | Out-File -Encoding ascii "$env:TEMP\del.json"
    q s3api delete-objects --bucket $s.bucket --delete ("file://" + ("$env:TEMP\del.json" -replace '\\','/'))
  }
} while ($objs.Count -gt 0)
q s3api delete-bucket --bucket $s.bucket

"RDS (takes ~5 min)"
q rds delete-db-instance --db-instance-identifier hospitaldb --skip-final-snapshot --delete-automated-backups
"EC2";          q ec2 terminate-instances --instance-ids $s.appInstance
& $aws ec2 wait instance-terminated --instance-ids $s.appInstance
& $aws rds wait db-instance-deleted --db-instance-identifier hospitaldb
q rds delete-db-subnet-group --db-subnet-group-name hospital-db-subnet-group

"IAM roles"
q iam detach-role-policy --role-name HospitalPatientAPIRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole
q iam delete-role --role-name HospitalPatientAPIRole
q iam detach-role-policy --role-name MedicalReportProcessorRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
q iam delete-role-policy --role-name MedicalReportProcessorRole --policy-name MedicalBucketAccess
q iam delete-role --role-name MedicalReportProcessorRole

"Security groups (waits for Lambda network interfaces to be released)"
q ec2 revoke-security-group-ingress --group-id $s.dbSg --ip-permissions "IpProtocol=tcp,FromPort=3306,ToPort=3306,UserIdGroupPairs=[{GroupId=$($s.webSg)},{GroupId=$($s.lambdaSg)}]"
for ($i = 0; $i -lt 60; $i++) {
  $enis = & $aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$($s.vpc)" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text
  if (-not $enis) { break }
  foreach ($e in ($enis -split '\s+')) { q ec2 delete-network-interface --network-interface-id $e }
  Start-Sleep -Seconds 20
}
foreach ($g in $s.dbSg, $s.lambdaSg, $s.webSg) { q ec2 delete-security-group --group-id $g }

"Network"
foreach ($sn in $s.pubSubnet, $s.privSubnet, $s.privSubnet2) { q ec2 delete-subnet --subnet-id $sn }
q ec2 delete-route-table --route-table-id $s.pubRt; q ec2 delete-route-table --route-table-id $s.privRt
q ec2 detach-internet-gateway --internet-gateway-id $s.igw --vpc-id $s.vpc; q ec2 delete-internet-gateway --internet-gateway-id $s.igw
q ec2 delete-vpc --vpc-id $s.vpc

"== Leftovers check =="
& $aws ec2 describe-vpcs --vpc-ids $s.vpc --query 'Vpcs[].VpcId' --output text 2>$null
& $aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier' --output text
& $aws lambda list-functions --query 'Functions[].FunctionName' --output text
& $aws amplify list-apps --query 'apps[].name' --output text
"Cleanup finished"
