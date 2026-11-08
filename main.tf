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
  availability_zone = data.aws_availability_zones.available.names[count.index]
   tags = {    
    Name = "vpf_tf_public-${count.index+1}"
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
}


resource "aws_eip" "nat" {
  count      = 2
  domain = "vpc"
}

resource "aws_nat_gateway" "vpf_tf_nat_gateway" {
  count      = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.vpf_tf_private_subnet[count.index].id # Must be a public subnet ID

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


resource "aws_security_group" "web_traffic" {
  
  vpc_id      = aws_vpc.vpf_tf.id  
  name        = "ssh_web_traffic_sg_tf"
  description = "Allow inbound SSH and HTTP traffic"
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For production, restrict this to your specific IP
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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


# 3. Define the EC2 Instance resource
resource "aws_instance" "bastion_tf" {
  ami           = "ami-0c230065b91270bc6" 
  instance_type = "t2.medium"
  tags = {
    Name = "bastion_tf"
  }
  subnet_id = aws_subnet.vpf_tf_public_subnet[0].id
  vpc_security_group_ids = [aws_security_group.web_traffic.id]
    user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd.x86_64
              systemctl start httpd.service
              systemctl enable httpd.service
              echo "Hello world from EC2 provisioned by Terraform! $(hostname -f)" > /var/www/html/index.html
              EOF
}

