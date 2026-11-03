# Question 2 – Scenario 1: Enterprise Web Application Deployment

**Where each command runs**

| Tag | Where |
|---|---|
| 🖥 **Console** | AWS Management Console (browser) |
| ☁ **CloudShell** | AWS CloudShell (icon `>_` at top bar of the console) – already has your credentials |
| 🐧 **EC2** | Terminal of the instance (EC2 → Instance → **Connect** → *EC2 Instance Connect* → Connect) |

Assumptions: Amazon Linux 2023, `t2.micro`, one region for everything. Replace anything in `<angle brackets>`.

---

## Q1. Launch EC2 in the specified VPC with a meaningful Name tag

🖥 **Console** → EC2 → **Launch instance**

1. **Name:** `WebApp-Prod-Server-01`
2. **AMI:** Amazon Linux 2023 · **Instance type:** `t2.micro`
3. **Key pair:** create/select one (e.g. `webapp-key`)
4. **Network settings → Edit**
   - **VPC:** the VPC given in the question
   - **Subnet:** a *public* subnet of that VPC
   - **Auto-assign public IP:** Enable
   - **Security group:** create `WebApp-SG`
     - SSH (22) → Source **My IP**
     - HTTP (80) → Source **Anywhere (0.0.0.0/0)**
5. **Advanced details**
   - **IAM instance profile:** `LabInstanceProfile` (AWS Academy Learner Lab) **or** a role with `AmazonS3FullAccess` + `CloudWatchReadOnlyAccess` (needed for Q5)
   - **Detailed CloudWatch monitoring:** Enable (1-minute metrics → alarms react faster in Q7)
6. **Launch instance**

Verify (☁ CloudShell):
```bash
aws ec2 describe-instances --filters "Name=tag:Name,Values=WebApp-Prod-Server-01" \
  --query 'Reservations[].Instances[].[InstanceId,VpcId,Placement.AvailabilityZone,PublicIpAddress,State.Name]' --output table
```
📸 Screenshot: instance list showing Name tag, VPC ID, Running state.

---

## Q2. Create & attach a 20 GB EBS volume, format XFS, mount permanently at `/webdata`

🖥 **Console** → EC2 → **Volumes** → **Create volume**
- Type `gp3`, Size `20` GiB
- **Availability Zone = same AZ as the instance** (check the instance's *Details* tab)
- Tag: `Name = WebData-Volume` → Create

Select volume → **Actions → Attach volume** → choose the instance → device `/dev/sdf` → Attach.

🐧 **EC2**
```bash
lsblk                                   # new 20G disk: xvdf (t2) or nvme1n1 (t3/Nitro)
DEV=/dev/xvdf                           # change to /dev/nvme1n1 if that is what lsblk shows
sudo file -s $DEV                       # "data" = empty disk, safe to format

sudo mkfs -t xfs $DEV
sudo mkdir -p /webdata
sudo mount $DEV /webdata

# Permanent mount using UUID (device names can change after reboot)
UUID=$(sudo blkid -s UUID -o value $DEV)
echo "UUID=$UUID  /webdata  xfs  defaults,nofail  0  2" | sudo tee -a /etc/fstab

# Test fstab without rebooting
sudo umount /webdata
sudo mount -a
df -hT /webdata
cat /etc/fstab
```
`nofail` = instance still boots if the volume is ever missing.
📸 Screenshot: `lsblk`, `df -hT /webdata` (shows **xfs, 20G**), `cat /etc/fstab`.

---

## Q3. Install Apache and point DocumentRoot to the EBS volume

🐧 **EC2**
```bash
sudo dnf install -y httpd php            # php is used for the dynamic page in Q4
sudo mkdir -p /webdata/html

# Change DocumentRoot and its <Directory> block
sudo sed -i 's#DocumentRoot "/var/www/html"#DocumentRoot "/webdata/html"#' /etc/httpd/conf/httpd.conf
sudo sed -i 's#<Directory "/var/www/html">#<Directory "/webdata/html">#'   /etc/httpd/conf/httpd.conf

sudo chown -R apache:apache /webdata/html
getenforce                               # AL2023 default = Permissive. If "Enforcing", run the next 2 lines:
# sudo semanage fcontext -a -t httpd_sys_content_t "/webdata(/.*)?"
# sudo restorecon -Rv /webdata

sudo apachectl configtest                # must say "Syntax OK"
sudo systemctl enable --now httpd php-fpm
grep -n "webdata" /etc/httpd/conf/httpd.conf
```
📸 Screenshot: `grep` output showing `DocumentRoot "/webdata/html"`, `systemctl status httpd`.

---

## Q4. Webpage: Instance ID, AZ, Date & Time, Hostname, auto-refresh every 30 s

Uses IMDSv2 (token-based metadata — required on Amazon Linux 2023).

🐧 **EC2**
```bash
sudo tee /webdata/html/index.php > /dev/null <<'EOF'
<?php
function imds($path) {
    $tok = @file_get_contents("http://169.254.169.254/latest/api/token", false,
        stream_context_create(["http" => ["method" => "PUT", "timeout" => 2,
            "header" => "X-aws-ec2-metadata-token-ttl-seconds: 21600"]]));
    $val = @file_get_contents("http://169.254.169.254/latest/meta-data/$path", false,
        stream_context_create(["http" => ["timeout" => 2,
            "header" => "X-aws-ec2-metadata-token: $tok"]]));
    return $val !== false ? htmlspecialchars($val) : "unavailable";
}
date_default_timezone_set("Asia/Kolkata");
?>
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="30">
  <title>Enterprise Web Application</title>
  <style>
    body { font-family: Arial, sans-serif; background:#f0f4f8; padding:40px; }
    .card { background:#fff; max-width:600px; margin:auto; padding:30px; border-radius:10px;
            box-shadow:0 2px 10px rgba(0,0,0,.1); }
    td { padding:8px 16px; } td:first-child { font-weight:bold; color:#333; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Enterprise Web Application</h1>
    <table>
      <tr><td>Instance ID</td><td><?= imds("instance-id") ?></td></tr>
      <tr><td>Availability Zone</td><td><?= imds("placement/availability-zone") ?></td></tr>
      <tr><td>Date &amp; Time</td><td><?= date("d-M-Y H:i:s T") ?></td></tr>
      <tr><td>Hostname</td><td><?= htmlspecialchars(gethostname()) ?></td></tr>
    </table>
    <p><small>Page auto-refreshes every 30 seconds. Served from /webdata (EBS).</small></p>
  </div>
</body>
</html>
EOF

sudo chown apache:apache /webdata/html/index.php
curl -s localhost | grep -A1 "<td>"      # quick check from inside the instance
```
Open `http://<PUBLIC_IP>` in the browser, wait 30 s → time changes on its own.
📸 Screenshot: browser page (two screenshots ~30 s apart show auto-refresh).

---

## Q5. Create S3 bucket & sync website directory with AWS CLI (preserving timestamps)

🐧 **EC2** (needs the IAM role from Q1)
```bash
TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
export AWS_DEFAULT_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

BUCKET=webapp-backup-<yourname>-$(date +%s)      # must be globally unique, lowercase
echo $BUCKET                                     # note it down
aws s3 mb s3://$BUCKET

# 1) Sync the website directory
aws s3 sync /webdata/html s3://$BUCKET/html/ --exact-timestamps
aws s3 ls s3://$BUCKET/html/ --recursive

# 2) Preserve original file timestamps: S3 always sets LastModified = upload time,
#    so also upload a tar archive (tar -p keeps mtime/permissions)
sudo tar -cpzf /tmp/webdata-html.tar.gz -C /webdata html
aws s3 cp /tmp/webdata-html.tar.gz s3://$BUCKET/archive/webdata-html.tar.gz

# Proof that timestamps are preserved: restore to /tmp and compare
mkdir -p /tmp/check && aws s3 cp s3://$BUCKET/archive/webdata-html.tar.gz /tmp/check/
tar -xpzf /tmp/check/webdata-html.tar.gz -C /tmp/check
stat -c '%n  %y' /webdata/html/index.php /tmp/check/html/index.php   # same mtime

# Proof that sync is incremental: change a file, sync again → only that file uploads
sudo touch /webdata/html/index.php
aws s3 sync /webdata/html s3://$BUCKET/html/ --exact-timestamps
```
`--exact-timestamps`: when syncing S3 → local, same-size files are skipped only when timestamps match exactly.
📸 Screenshot: `aws s3 ls`, the two `stat` lines with matching times.

---

## Q6. CloudWatch alarms: CPU > 70 %, Disk Read Ops, Disk Write Ops, Status Check Failed

☁ **CloudShell**
```bash
INSTANCE_ID=<i-xxxxxxxx>
VOLUME_ID=<vol-xxxxxxxx>          # the 20 GB WebData-Volume
EMAIL=<your-email>

# SNS topic for notifications (confirm the subscription in your email inbox!)
TOPIC_ARN=$(aws sns create-topic --name WebApp-Alerts --query TopicArn --output text)
aws sns subscribe --topic-arn $TOPIC_ARN --protocol email --notification-endpoint $EMAIL

aws ec2 monitor-instances --instance-ids $INSTANCE_ID     # detailed (1-min) monitoring

# 1) CPU > 70 %
aws cloudwatch put-metric-alarm --alarm-name WebApp-HighCPU \
  --namespace AWS/EC2 --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --statistic Average --period 60 --evaluation-periods 2 \
  --threshold 70 --comparison-operator GreaterThanThreshold \
  --alarm-actions $TOPIC_ARN --ok-actions $TOPIC_ARN

# 2) Disk Read Operations (EBS volume)
aws cloudwatch put-metric-alarm --alarm-name WebApp-DiskReadOps \
  --namespace AWS/EBS --metric-name VolumeReadOps \
  --dimensions Name=VolumeId,Value=$VOLUME_ID \
  --statistic Sum --period 60 --evaluation-periods 1 \
  --threshold 1000 --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching --alarm-actions $TOPIC_ARN

# 3) Disk Write Operations (EBS volume)
aws cloudwatch put-metric-alarm --alarm-name WebApp-DiskWriteOps \
  --namespace AWS/EBS --metric-name VolumeWriteOps \
  --dimensions Name=VolumeId,Value=$VOLUME_ID \
  --statistic Sum --period 60 --evaluation-periods 1 \
  --threshold 1000 --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching --alarm-actions $TOPIC_ARN

# 4) Status Check Failed
aws cloudwatch put-metric-alarm --alarm-name WebApp-StatusCheckFailed \
  --namespace AWS/EC2 --metric-name StatusCheckFailed \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --statistic Maximum --period 60 --evaluation-periods 2 \
  --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions $TOPIC_ARN

aws cloudwatch describe-alarms --alarm-name-prefix WebApp \
  --query 'MetricAlarms[].[AlarmName,MetricName,Threshold,StateValue]' --output table
```

> **Why `AWS/EBS VolumeReadOps` instead of EC2 `DiskReadOps`?** The EC2 metrics `DiskReadOps`/`DiskWriteOps` only count **instance-store** disks. A t2.micro has only EBS, so those stay at 0 / *Insufficient data*. The EBS metrics are the ones that move. (On t3/Nitro instances `AWS/EC2 EBSReadOps`/`EBSWriteOps` also work.) Mention this if the examiner asks.

**Console alternative (CPU alarm):** CloudWatch → Alarms → **Create alarm** → Select metric → EC2 → Per-Instance Metrics → your instance `CPUUtilization` → Average, 1 minute → *Greater than 70* → 2 out of 2 datapoints → Notification: *In alarm* → topic `WebApp-Alerts` → Name `WebApp-HighCPU` → Create. Repeat with EBS → Per-Volume → `VolumeReadOps` / `VolumeWriteOps`, and EC2 `StatusCheckFailed`.

📸 Screenshot: CloudWatch → Alarms list with all 4 alarms.

---

## Q7. Generate CPU load for 5 minutes and capture alarm state transitions

🐧 **EC2**
```bash
sudo dnf install -y stress-ng
stress-ng --cpu $(nproc) --cpu-load 100 --timeout 300s --metrics-brief &
top            # shows ~100% CPU; press q to exit (stress keeps running in background)

# Fallback if stress-ng is unavailable:
# timeout 300 sh -c 'for i in $(seq $(nproc)); do yes > /dev/null & done; wait'

# Optional: also trigger the disk alarms
sudo dd if=/dev/zero of=/webdata/test.img bs=4k count=50000 oflag=direct     # write ops
sudo dd if=/webdata/test.img of=/dev/null bs=4k iflag=direct                  # read ops
sudo rm -f /webdata/test.img
```

☁ **CloudShell** – watch the state change live:
```bash
watch -n 30 "aws cloudwatch describe-alarms --alarm-name-prefix WebApp \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output table"
# Ctrl+C to stop watching
```

After the 5 minutes + ~3 min for it to return to OK:
```bash
aws cloudwatch describe-alarm-history --alarm-name WebApp-HighCPU \
  --history-item-type StateUpdate \
  --query 'AlarmHistoryItems[].[Timestamp,HistorySummary]' --output table
```
Expected transitions: `INSUFFICIENT_DATA → OK` → `OK → ALARM` (≈2–3 min after load starts) → `ALARM → OK` (after load stops). You also get ALARM and OK emails.
📸 Screenshot: `top`, alarm in red **In alarm**, CPU graph spike, alarm *History* tab, email notification.

---

## Q8. EBS snapshot without stopping the instance; delete webpage; restore from snapshot

**1. Take the snapshot (instance keeps running)**

🐧 **EC2** – optional: freeze the filesystem for a clean, consistent snapshot
```bash
sudo sync && sudo xfs_freeze -f /webdata
```
☁ **CloudShell**
```bash
SNAP_ID=$(aws ec2 create-snapshot --volume-id $VOLUME_ID \
  --description "WebData backup - live instance" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=WebData-Snapshot}]' \
  --query SnapshotId --output text)
echo $SNAP_ID
```
🐧 **EC2** – unfreeze right after the command returns (snapshot is point-in-time from that moment)
```bash
sudo xfs_freeze -u /webdata
```
☁ **CloudShell**
```bash
aws ec2 wait snapshot-completed --snapshot-ids $SNAP_ID && echo "Snapshot completed"
aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].State.Name'   # still "running"
```
(Console way: EC2 → Volumes → select WebData-Volume → Actions → **Create snapshot**.)

**2. Delete the webpage**

🐧 **EC2**
```bash
sudo rm /webdata/html/index.php
curl -I localhost            # 403 / default test page → website is gone
```
📸 Screenshot: browser showing page missing.

**3. Restore from snapshot**

☁ **CloudShell**
```bash
AZ=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)

RVOL=$(aws ec2 create-volume --snapshot-id $SNAP_ID --availability-zone $AZ --volume-type gp3 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=WebData-Restore}]' \
  --query VolumeId --output text)
aws ec2 wait volume-available --volume-ids $RVOL
aws ec2 attach-volume --volume-id $RVOL --instance-id $INSTANCE_ID --device /dev/sdg
```
🐧 **EC2**
```bash
lsblk                                         # new disk: xvdg (or nvme2n1)
sudo mkdir -p /mnt/restore
sudo mount -o nouuid /dev/xvdg /mnt/restore   # nouuid is REQUIRED: snapshot copy has the same XFS UUID as /webdata
ls -l /mnt/restore/html/
sudo cp -a /mnt/restore/html/index.php /webdata/html/
sudo umount /mnt/restore
curl -s localhost | grep "Instance ID"        # website is back
```
☁ **CloudShell** – remove the temporary restore volume
```bash
aws ec2 detach-volume --volume-id $RVOL
aws ec2 wait volume-available --volume-ids $RVOL
aws ec2 delete-volume --volume-id $RVOL
```
📸 Screenshot: snapshot *Completed*, `ls /mnt/restore/html`, browser showing page restored.

---

## Q9. Terminate instance, launch a new one, restore snapshot, verify website

**1. Terminate the old instance**

🖥 **Console** → EC2 → select `WebApp-Prod-Server-01` → **Instance state → Terminate**.
(The 20 GB volume is *not* deleted automatically because it was attached later; we will clean it up at the end. The snapshot is our backup.)

**2. Launch a new instance**

🖥 Same steps as Q1, but:
- **Name:** `WebApp-Prod-Server-02`
- Same VPC/subnet, **same security group `WebApp-SG`**, same key pair & IAM profile
- **Advanced details → User data:**
```bash
#!/bin/bash
dnf install -y httpd php
mkdir -p /webdata/html
sed -i 's#DocumentRoot "/var/www/html"#DocumentRoot "/webdata/html"#' /etc/httpd/conf/httpd.conf
sed -i 's#<Directory "/var/www/html">#<Directory "/webdata/html">#'   /etc/httpd/conf/httpd.conf
systemctl enable --now httpd php-fpm
```

**3. Create a volume from the snapshot and attach it**

☁ **CloudShell**
```bash
NEW_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=WebApp-Prod-Server-02" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
NEW_AZ=$(aws ec2 describe-instances --instance-ids $NEW_ID \
  --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)

NVOL=$(aws ec2 create-volume --snapshot-id $SNAP_ID --availability-zone $NEW_AZ --volume-type gp3 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=WebData-Volume-Restored}]' \
  --query VolumeId --output text)
aws ec2 wait volume-available --volume-ids $NVOL
aws ec2 attach-volume --volume-id $NVOL --instance-id $NEW_ID --device /dev/sdf
```

**4. Mount and verify**

🐧 **EC2** (connect to the *new* instance)
```bash
lsblk
DEV=/dev/xvdf                                  # or /dev/nvme1n1
sudo mount $DEV /webdata                       # no mkfs! data comes from the snapshot
UUID=$(sudo blkid -s UUID -o value $DEV)
echo "UUID=$UUID  /webdata  xfs  defaults,nofail  0  2" | sudo tee -a /etc/fstab
sudo umount /webdata && sudo mount -a && df -hT /webdata
ls -l /webdata/html
sudo systemctl restart httpd
curl -s localhost | grep -A1 "<td>"
```
Open `http://<NEW_PUBLIC_IP>` → the same page loads, now showing the **new Instance ID** (and possibly a different AZ) – proof the site was restored from the snapshot onto a new server.
📸 Screenshot: old instance *Terminated*, new instance *Running*, browser page with the new Instance ID.

(Optional: point the CloudWatch alarms at `$NEW_ID` / `$NVOL` by re-running the Q6 commands with the new IDs.)

---

## Cleanup (avoid charges)

☁ **CloudShell**
```bash
aws ec2 terminate-instances --instance-ids $NEW_ID
aws ec2 wait instance-terminated --instance-ids $NEW_ID
aws ec2 delete-volume --volume-id $NVOL
aws ec2 delete-volume --volume-id $VOLUME_ID          # original 20 GB volume
aws ec2 delete-snapshot --snapshot-id $SNAP_ID
aws s3 rb s3://$BUCKET --force                        # empties + deletes bucket (set BUCKET first)
aws cloudwatch delete-alarms --alarm-names WebApp-HighCPU WebApp-DiskReadOps WebApp-DiskWriteOps WebApp-StatusCheckFailed
aws sns delete-topic --topic-arn $TOPIC_ARN
# Security group last (after instances are gone):
# aws ec2 delete-security-group --group-id <sg-xxxxxxxx>
```

---

## Common pitfalls

| Problem | Fix |
|---|---|
| Volume can't be attached | Volume and instance must be in the **same AZ** |
| `mount: wrong fs type` on restored volume | Use `mount -o nouuid` when the original volume is mounted at the same time |
| `aws s3 ...` → *Unable to locate credentials* on EC2 | Attach IAM role / `LabInstanceProfile` (EC2 → Actions → Security → Modify IAM role) |
| `aws s3 mb` → region error | `export AWS_DEFAULT_REGION=...` (see Q5) |
| Browser can't reach site | SG must allow port 80; use `http://` not `https://` |
| SSH times out | SG SSH rule is *My IP* – your IP may have changed; edit the rule |
| Alarm never fires | Confirm SNS email subscription; detailed monitoring on; wait 2–3 min |
| Page shows "unavailable" for Instance ID | IMDS disabled – EC2 → Actions → Instance settings → Modify instance metadata options → Enable |
