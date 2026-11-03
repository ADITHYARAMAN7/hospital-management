$ErrorActionPreference = "Stop"
$aws = "$env:LOCALAPPDATA\Programs\Amazon\AWSCLIV2\aws.exe"
$dir = "D:\AA sem 7\Cloud_endsem\hospital"
$s = Get-Content "$dir\state.json" | ConvertFrom-Json

# Build: copy site and inject the API URL
$dist = "$dir\dist"
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
Copy-Item "$dir\site" $dist -Recurse
$js = [IO.File]::ReadAllText("$dist\script.js").Replace("__API_URL__", $s.apiUrl)
[IO.File]::WriteAllText("$dist\script.js", $js, (New-Object Text.UTF8Encoding $false))
$zip = "$dir\site.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path "$dist\*" -DestinationPath $zip

# Manual deployment (no Git): create deployment -> upload zip -> start
$dep = & $aws amplify create-deployment --app-id $s.amplifyAppId --branch-name main --query '[jobId,zipUploadUrl]' --output text
$jobId, $uploadUrl = $dep -split "`t"
curl.exe -s -f -X PUT -H "Content-Type: application/zip" --upload-file $zip $uploadUrl
& $aws amplify start-deployment --app-id $s.amplifyAppId --branch-name main --job-id $jobId --query 'jobSummary.status' --output text

do {
  Start-Sleep -Seconds 5
  $st = & $aws amplify get-job --app-id $s.amplifyAppId --branch-name main --job-id $jobId --query 'job.summary.status' --output text
  "job $jobId : $st"
} while ($st -in @("PENDING", "PROVISIONING", "RUNNING", "CREATED"))
$s.amplifyUrl
