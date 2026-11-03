$ErrorActionPreference = "Stop"
$aws = "$env:LOCALAPPDATA\Programs\Amazon\AWSCLIV2\aws.exe"
$dir = "D:\AA sem 7\Cloud_endsem\hospital"
$s = Get-Content "$dir\state.json" | ConvertFrom-Json
$acct = & $aws sts get-caller-identity --query Account --output text
$bucket = "hospital-medical-records-$acct"

& $aws s3api create-bucket --bucket $bucket --region us-east-1 | Out-Null
& $aws s3api wait bucket-exists --bucket $bucket
& $aws s3api put-public-access-block --bucket $bucket --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
& $aws s3api put-bucket-ownership-controls --bucket $bucket --ownership-controls "Rules=[{ObjectOwnership=BucketOwnerEnforced}]"
& $aws s3api put-bucket-versioning --bucket $bucket --versioning-configuration Status=Enabled
& $aws s3api put-bucket-tagging --bucket $bucket --tagging "TagSet=[{Key=Name,Value=$bucket},{Key=Project,Value=HospitalMS}]"

# Bucket policy: deny any non-HTTPS access (medical data must be encrypted in transit)
$policy = @"
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyInsecureTransport",
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:*",
    "Resource": ["arn:aws:s3:::$bucket", "arn:aws:s3:::$bucket/*"],
    "Condition": { "Bool": { "aws:SecureTransport": "false" } }
  }]
}
"@
$policy | Out-File -Encoding ascii "$dir\bucket-policy.json"
& $aws s3api put-bucket-policy --bucket $bucket --policy ("file://" + ("$dir\bucket-policy.json" -replace '\\','/'))

& $aws s3 cp "$dir\files\scan.jpg" "s3://$bucket/diagnostic-images/scan.jpg" --content-type image/jpeg
& $aws s3 cp "$dir\files\medical-report.pdf" "s3://$bucket/medical-reports/medical-report.pdf" --content-type application/pdf

$s | Add-Member -NotePropertyName bucket -NotePropertyValue $bucket -Force
$s | ConvertTo-Json | Out-File -Encoding utf8 "$dir\state.json"
$bucket
