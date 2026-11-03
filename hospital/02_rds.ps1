$ErrorActionPreference = "Stop"
$aws = "$env:LOCALAPPDATA\Programs\Amazon\AWSCLIV2\aws.exe"
$dir = "D:\AA sem 7\Cloud_endsem\hospital"
$s = Get-Content "$dir\state.json" | ConvertFrom-Json

$chars = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
$pw = -join (1..20 | ForEach-Object { $chars | Get-Random })
@{ dbUser = "admin"; dbPassword = $pw; dbName = "HospitalDB" } | ConvertTo-Json | Out-File -Encoding utf8 "$dir\db-secret.json"

& $aws rds create-db-subnet-group --db-subnet-group-name hospital-db-subnet-group `
  --db-subnet-group-description "HospitalVPC private subnets for HospitalDB" `
  --subnet-ids $s.privSubnet $s.privSubnet2 `
  --tags Key=Name,Value=hospital-db-subnet-group Key=Project,Value=HospitalMS --query DBSubnetGroup.DBSubnetGroupName --output text

& $aws rds create-db-instance --db-instance-identifier hospitaldb `
  --db-name HospitalDB --engine mysql --db-instance-class db.t3.micro `
  --allocated-storage 20 --storage-type gp2 `
  --master-username admin --master-user-password $pw `
  --db-subnet-group-name hospital-db-subnet-group --vpc-security-group-ids $s.dbSg `
  --availability-zone us-east-1a --no-publicly-accessible --no-multi-az `
  --backup-retention-period 0 --storage-encrypted `
  --tags Key=Name,Value=HospitalDB Key=Project,Value=HospitalMS `
  --query 'DBInstance.[DBInstanceIdentifier,DBInstanceStatus,Engine,EngineVersion]' --output text
