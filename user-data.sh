#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd

# Write instance metadata to index.html
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
echo "<h1>Hello from EC2 instance: $INSTANCE_ID</h1>" > /var/www/html/index.html
