# -----------------------------
# PROVIDER CONFIGURATION
# -----------------------------
provider "aws" {
  region = "us-east-1"  # Set AWS region for all resources
}

# -----------------------------
# CREATE A KEY PAIR
# -----------------------------
resource "aws_key_pair" "my_key" {
  key_name   = "my-ec2-key"                     # Name of the key pair
  public_key = file("~/.ssh/my-ec2-key.pub")    # Read public key from your local SSH directory
}

# -----------------------------
# SECURITY GROUP FOR EC2 & ALB
# -----------------------------
resource "aws_security_group" "web_sg" {
  name        = "allow_http"                      # Name of the security group
  description = "Allow HTTP and SSH inbound traffic"

  # Allow SSH from anywhere (for remote access)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP traffic from anywhere (for web access)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"              # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------
# FETCH DEFAULT VPC AND SUBNETS
# -----------------------------
data "aws_vpc" "default" {
  default = true                     # Use the default VPC in the selected region
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]  # Get subnets that belong to the default VPC
  }
}

# -----------------------------
# CREATE 2 EC2 INSTANCES
# -----------------------------
resource "aws_instance" "web" {
  count                  = 2                        # Launch 2 instances
  ami                    = "ami-0c2b8ca1dad447f8a"  # Amazon Linux 2 AMI (for us-east-1)
  instance_type          = "t2.micro"               # Small free-tier eligible instance
  key_name               = aws_key_pair.my_key.key_name  # Use the key pair defined above
  vpc_security_group_ids = [aws_security_group.web_sg.id] # Attach the security group
  subnet_id              = data.aws_subnets.default.ids[count.index] # Spread EC2s across subnets

  user_data = file("user-data.sh")   # Bootstrap script to install web server

  tags = {
    Name = "WebServer-${count.index + 1}"   # Give each instance a unique name
  }
}

# -----------------------------
# CREATE A TARGET GROUP FOR ALB
# -----------------------------
resource "aws_lb_target_group" "web_tg" {
  name     = "web-tg"
  port     = 80                          # Target listens on port 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  # Health check settings for the ALB to know if instance is healthy
  health_check {
    path                = "/"            # Health check URL path
    protocol            = "HTTP"
    interval            = 30             # Time between health checks
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# -----------------------------
# ATTACH EC2 INSTANCES TO ALB TARGET GROUP
# -----------------------------
resource "aws_lb_target_group_attachment" "web_attachments" {
  count            = 2                                          # Attach both instances
  target_group_arn = aws_lb_target_group.web_tg.arn             # Reference the target group
  target_id        = aws_instance.web[count.index].id           # Target is the EC2 instance
  port             = 80                                         # Instance listens on port 80
}

# -----------------------------
# CREATE APPLICATION LOAD BALANCER
# -----------------------------
resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false                                   # Set to false so it's internet-facing
  load_balancer_type = "application"                           # Type is Application Load Balancer (ALB)
  security_groups    = [aws_security_group.web_sg.id]          # Attach same security group as EC2
  subnets            = data.aws_subnets.default.ids            # Spread ALB across all subnets

  enable_deletion_protection = false
}

# -----------------------------
# ALB LISTENER - HTTP TRAFFIC
# -----------------------------
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn     # Reference the ALB
  port              = 80                     # Listen on port 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"                     # Forward traffic to target group
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# -----------------------------
# OUTPUT THE ALB DNS NAME
# -----------------------------
output "alb_dns_name" {
  value = aws_lb.web_alb.dns_name           # Print ALB public DNS after apply
}
