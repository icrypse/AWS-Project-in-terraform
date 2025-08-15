provider "aws" {
  region = "us-east-1"  
}

resource "aws_key_pair" "my_key" {
  key_name   = "my-ec2-key"
  public_key = file("~/.ssh/my-ec2-key.pub")
}

resource "aws_security_group" "web_sg"{
    name = "allow_http"
    description = "allow_http and ssh inbound traffic"

    ingress {
        from_port =22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port =0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_instance" "web" {
  ami                    = "ami-0c2b8ca1dad447f8a" # Amazon Linux 2 (for us-east-1)
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.my_key.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = file("user-data.sh")

  tags = {
    Name = "Terraform-Web-Server"
  }
}

