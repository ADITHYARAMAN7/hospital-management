$ErrorActionPreference = "Stop"
$aws = "$env:LOCALAPPDATA\Programs\Amazon\AWSCLIV2\aws.exe"
$stateFile = "D:\AA sem 7\Cloud_endsem\hospital\state.json"
function tags($name) { "ResourceType={0},Tags=[{{Key=Name,Value=$name}},{{Key=Project,Value=HospitalMS}}]" }

$myIp = (curl.exe -s https://checkip.amazonaws.com).Trim()

# VPC
$vpc = & $aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications ((tags "HospitalVPC") -f "vpc") --query Vpc.VpcId --output text
& $aws ec2 wait vpc-available --vpc-ids $vpc
& $aws ec2 modify-vpc-attribute --vpc-id $vpc --enable-dns-support '{"Value":true}'
& $aws ec2 modify-vpc-attribute --vpc-id $vpc --enable-dns-hostnames '{"Value":true}'

# Subnets
$pub  = & $aws ec2 create-subnet --vpc-id $vpc --cidr-block 10.0.1.0/24 --availability-zone us-east-1a --tag-specifications ((tags "Hospital-Public-Subnet") -f "subnet") --query Subnet.SubnetId --output text
$priv = & $aws ec2 create-subnet --vpc-id $vpc --cidr-block 10.0.2.0/24 --availability-zone us-east-1a --tag-specifications ((tags "Hospital-Private-Subnet") -f "subnet") --query Subnet.SubnetId --output text
# RDS requires a DB subnet group spanning 2 AZs -> standby private subnet (DB itself runs in us-east-1a)
$priv2 = & $aws ec2 create-subnet --vpc-id $vpc --cidr-block 10.0.3.0/24 --availability-zone us-east-1b --tag-specifications ((tags "Hospital-Private-Subnet-DB-Standby") -f "subnet") --query Subnet.SubnetId --output text
& $aws ec2 modify-subnet-attribute --subnet-id $pub --map-public-ip-on-launch

# Internet Gateway
$igw = & $aws ec2 create-internet-gateway --tag-specifications ((tags "Hospital-IGW") -f "internet-gateway") --query InternetGateway.InternetGatewayId --output text
& $aws ec2 attach-internet-gateway --internet-gateway-id $igw --vpc-id $vpc

# Route tables
$pubRt = & $aws ec2 create-route-table --vpc-id $vpc --tag-specifications ((tags "Hospital-Public-RT") -f "route-table") --query RouteTable.RouteTableId --output text
& $aws ec2 create-route --route-table-id $pubRt --destination-cidr-block 0.0.0.0/0 --gateway-id $igw | Out-Null
& $aws ec2 associate-route-table --route-table-id $pubRt --subnet-id $pub | Out-Null
$privRt = & $aws ec2 create-route-table --vpc-id $vpc --tag-specifications ((tags "Hospital-Private-RT") -f "route-table") --query RouteTable.RouteTableId --output text
& $aws ec2 associate-route-table --route-table-id $privRt --subnet-id $priv | Out-Null
& $aws ec2 associate-route-table --route-table-id $privRt --subnet-id $priv2 | Out-Null

# Security groups
$webSg = & $aws ec2 create-security-group --group-name Hospital-Web-SG --description "Web/app server: HTTP/HTTPS from internet, SSH from admin + EC2 Instance Connect" --vpc-id $vpc --tag-specifications ((tags "Hospital-Web-SG") -f "security-group") --query GroupId --output text
& $aws ec2 authorize-security-group-ingress --group-id $webSg --ip-permissions `
  "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description=HTTP-web-traffic}]" `
  "IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0,Description=HTTPS-web-traffic}]" `
  "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$myIp/32,Description=Admin-SSH},{CidrIp=18.206.107.24/29,Description=EC2-Instance-Connect-us-east-1}]" | Out-Null

$lambdaSg = & $aws ec2 create-security-group --group-name Hospital-Lambda-SG --description "Patient API Lambda - no inbound, outbound to DB" --vpc-id $vpc --tag-specifications ((tags "Hospital-Lambda-SG") -f "security-group") --query GroupId --output text

$dbSg = & $aws ec2 create-security-group --group-name Hospital-DB-SG --description "RDS MySQL - 3306 only from authorized app resources" --vpc-id $vpc --tag-specifications ((tags "Hospital-DB-SG") -f "security-group") --query GroupId --output text
& $aws ec2 authorize-security-group-ingress --group-id $dbSg --ip-permissions `
  "IpProtocol=tcp,FromPort=3306,ToPort=3306,UserIdGroupPairs=[{GroupId=$webSg,Description=From-App-Server},{GroupId=$lambdaSg,Description=From-Patient-API-Lambda}]" | Out-Null

$state = [ordered]@{ myIp=$myIp; vpc=$vpc; pubSubnet=$pub; privSubnet=$priv; privSubnet2=$priv2; igw=$igw; pubRt=$pubRt; privRt=$privRt; webSg=$webSg; lambdaSg=$lambdaSg; dbSg=$dbSg }
$state | ConvertTo-Json | Out-File -Encoding utf8 $stateFile
$state
