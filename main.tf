# PROVIDER
# --------
provider "aws" {
  region = "us-east-1"  # Set AWS region to us-east-1
}

# KEY PAIR
# --------
resource "aws_key_pair" "my_key" {
  key_name   = "my-ec2-key"                     # Name of the key pair
  public_key = file("~/.ssh/my-ec2-key.pub")   # Use your existing SSH public key file
}

# SECURITY GROUP for EC2 and ALB
# ------------------------------
resource "aws_security_group" "web_sg" {
  name        = "allow_http_ssh"                  # Security group name
  description = "Allow inbound HTTP (80) and SSH (22) traffic"

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]                   # Open to anywhere (adjust for security)
  }

  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]                   # Open HTTP traffic from anywhere
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# FETCH DEFAULT VPC AND SUBNETS
# -----------------------------
data "aws_vpc" "default" {
  default = true                         # Select the default VPC in the region
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]  # Filter subnets belonging to the default VPC
  }
}

# LAUNCH TEMPLATE
# ---------------
resource "aws_launch_template" "web_lt" {
  name_prefix   = "web-server-"          # Prefix for LT name
  image_id      = "ami-0c2b8ca1dad447f8a"  # Amazon Linux 2 AMI ID (us-east-1)
  instance_type = "t2.micro"              # Instance size
  key_name      = aws_key_pair.my_key.key_name  # SSH key name to use
  vpc_security_group_ids = [aws_security_group.web_sg.id]  # Attach security group

  # User data script for instance bootstrap (base64 encoded automatically)
  user_data = filebase64("user-data.sh")

  lifecycle {
    create_before_destroy = true          # Create new LT before deleting old one on update
  }
}

# AUTO SCALING GROUP (ASG)
# ------------------------
resource "aws_autoscaling_group" "web_asg" {
  desired_capacity     = 2                    # Number of instances to maintain
  max_size             = 3                    # Maximum number of instances
  min_size             = 1                    # Minimum number of instances
  vpc_zone_identifier  = data.aws_subnets.default.ids  # Subnets to launch instances in

  launch_template {
    id      = aws_launch_template.web_lt.id   # Use Launch Template for config
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.web_tg.arn]  # Attach to ALB target group

  health_check_type         = "ELB"       # Use ELB health checks for instances
  health_check_grace_period = 300         # Wait 5 minutes before checking health

  tag {
    key                 = "Name"
    value               = "ASG-WebServer"
    propagate_at_launch = true            # Apply tag to launched instances
  }

  force_delete = true                      # Allow deletion of ASG even if instances exist
}

# SCALING POLICIES
# ----------------
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
  scaling_adjustment     = 1               # Increase capacity by 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300             # Wait 5 minutes before another scaling action
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down"
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
  scaling_adjustment     = -1              # Decrease capacity by 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
}

# CLOUDWATCH ALARMS
# -----------------
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "high_cpu_alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2                   # Number of evaluation periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120                 # Alarm checks every 2 minutes
  statistic           = "Average"
  threshold           = 70                  # Alarm triggers if average CPU > 70%

  alarm_actions = [aws_autoscaling_policy.scale_up.arn]  # Trigger scale-up policy

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "low_cpu_alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 30                  # Alarm triggers if average CPU < 30%

  alarm_actions = [aws_autoscaling_policy.scale_down.arn]  # Trigger scale-down policy

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
}
