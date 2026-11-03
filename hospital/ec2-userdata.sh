#!/bin/bash
dnf install -y mariadb105 httpd
TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html><html><head><title>Hospital App Server</title>
<style>body{font-family:Segoe UI,Arial;background:#eef6f8;margin:0;padding:60px}
.c{max-width:640px;margin:auto;background:#fff;border-radius:12px;padding:32px;box-shadow:0 4px 20px rgba(0,0,0,.08)}
h1{color:#0b7285;margin-top:0}td{padding:6px 14px}td:first-child{font-weight:600}</style></head>
<body><div class="c"><h1>&#x1F3E5; Hospital App Server</h1>
<p>Application tier inside <b>HospitalVPC</b> (public subnet). Only this server and the Patient API Lambda may reach the RDS database.</p>
<table><tr><td>Instance ID</td><td>$IID</td></tr><tr><td>Availability Zone</td><td>$AZ</td></tr>
<tr><td>VPC CIDR</td><td>10.0.0.0/16</td></tr><tr><td>Subnet</td><td>Hospital-Public-Subnet (10.0.1.0/24)</td></tr></table></div></body></html>
EOF
systemctl enable --now httpd
