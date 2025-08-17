output "instance_ip" {
  #value = aws_instance.web.public_ip  # for single instance
  value = [for instance in aws_instance.web : instance.public_ip]
  description = "Public IP of the EC2 instance"
}
