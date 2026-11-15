# 1. Specify the required provider and version
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.2.0"
}

# 2. Configure the AWS Provider and target region
provider "aws" {
  region     = "us-east-1"
}

terraform {
  backend "s3" {
    bucket  = "s3tfstatesafespringboot" # <-- Must match the bucket name above
    key     = "springboot-app/terraform.tfstate"         # <-- The exact path/filename inside S3
    region  = "us-east-1"
    encrypt = true
  }
}

resource "aws_vpc" "vpf_tf" {
  cidr_block = "10.0.0.0/16"
  tags = {  
    Name = "vpf_tf"
  }
}

resource "aws_internet_gateway" "vpf_tf_internet_gateway" {
  vpc_id = aws_vpc.vpf_tf.id
}

resource "aws_route_table" "vpf_tf_public_route_table" {
  vpc_id = aws_vpc.vpf_tf.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vpf_tf_internet_gateway.id
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "vpf_tf_public_subnet" {
  count      = 2
  cidr_block = "10.0.${count.index + 1}.0/24"
  vpc_id     = aws_vpc.vpf_tf.id
  map_public_ip_on_launch = true 
  availability_zone = data.aws_availability_zones.available.names[count.index]
   tags = {    
    Name = "vpf_tf_public_subnet-${count.index+1}"
  }

}

resource "aws_route_table_association" "vpf_tf_public_route_table_association" {
  count          = 2
  subnet_id      = aws_subnet.vpf_tf_public_subnet[count.index].id
  route_table_id = aws_route_table.vpf_tf_public_route_table.id
}

resource "aws_subnet" "vpf_tf_private_subnet" {
  count      = 2
  cidr_block = "10.0.${count.index + 3}.0/24"
  vpc_id     = aws_vpc.vpf_tf.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
   tags = {    
    Name = "vpf_tf_private_subnet-${count.index+1}"
  }
}


resource "aws_eip" "nat" {
  count      = 2
  domain = "vpc"
}

resource "aws_nat_gateway" "vpf_tf_nat_gateway" {
  count      = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.vpf_tf_public_subnet[count.index].id # Must be a public subnet ID
  connectivity_type = "public"
  tags = {  
    Name = "vpf_tf_nat_gateway_${count.index+1}"
  }

  # Recommended practice to ensure correct creation ordering
  depends_on = [aws_internet_gateway.vpf_tf_internet_gateway]
}


resource "aws_route_table" "vpf_tf_private_route_table" {
  count      = 2
  vpc_id = aws_vpc.vpf_tf.id
  route {
    cidr_block     = "0.0.0.0/0"
    gateway_id     = aws_nat_gateway.vpf_tf_nat_gateway[count.index].id
  }
}
resource "aws_route_table_association" "vpf_tf_private_route_table_association"{
  count          = 2
  subnet_id      = aws_subnet.vpf_tf_private_subnet[count.index].id
  route_table_id = aws_route_table.vpf_tf_private_route_table[count.index].id
}

resource "aws_security_group" "alb_sg" {
  name        = "alb_sg_tf"
  description = "Allow HTTP inbound traffic to ALB"
  vpc_id      = aws_vpc.vpf_tf.id  

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}  

resource "aws_security_group" "bastion_sg" {
  vpc_id      = aws_vpc.vpf_tf.id  
  name        = "ssh_traffic_sg_tf"
  description = "Allow inbound SSH and HTTP traffic"
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For production, restrict this to your specific IP
  }
  # Outbound Rules (Egress)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # "-1" means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "ssh_web_traffic_sg_tf"
  }
}

resource "aws_security_group" "web_sg" {
  name        = "web_sg_tf"
  description = "Allow HTTP inbound traffic from ALB"
  vpc_id      = aws_vpc.vpf_tf.id  

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [ aws_security_group.alb_sg.id ] # Allow traffic from ALB security group
  }
   egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
} 


# 3. Define the EC2 Instance resource
resource "aws_instance" "bastion_ec2" {
  ami           = "ami-0c230065b91270bc6" 
  instance_type = "t2.medium"
  tags = {
    Name = "bastion_tf"
  }
  associate_public_ip_address = true
  subnet_id = aws_subnet.vpf_tf_public_subnet[0].id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]   
  
}

resource "aws_instance" "ec2_web" {
  ami           = "ami-0c230065b91270bc6" 
  instance_type = "t2.medium"
  tags = {
    Name = "bastion_tf"
  }
  count      = 2
  subnet_id = aws_subnet.vpf_tf_private_subnet[0].id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
    user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd.x86_64
              systemctl start httpd.service
              systemctl enable httpd.service
              echo "Hello world from EC2 provisioned by Terraform! $(hostname -f)" > /var/www/html/index.html
              EOF
}

resource "aws_lb" "app_alb_tf" {
  name               = "appalbtf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.vpf_tf_public_subnet[*].id

  enable_deletion_protection = false

  tags = {
    Name = "app_alb_tf"
  }
}

# 4. Target Group
resource "aws_lb_target_group" "app_tg_tf" {
  name        = "apptgtf"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpf_tf.id
  target_type = "instance" # Use "ip" for ECS Fargate

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "app_tg_tf"
  }
}

# 5. HTTP Listener (Routes port 80 traffic to the Target Group)
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_alb_tf.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg_tf.arn
  }
}

# 6. Optional: Attach EC2 Instances to the Target Group
resource "aws_lb_target_group_attachment" "ec2_attach" {
  count            = length(aws_instance.ec2_web)
  target_group_arn = aws_lb_target_group.app_tg_tf.arn
  target_id        = aws_instance.ec2_web[count.index].id
  port             = 80
}

# 7. Outputs
output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.app_alb_tf.dns_name
}

output "target_group_arn" {
  description = "The ARN of the Target Group"
  value       = aws_lb_target_group.app_tg_tf.arn
}

