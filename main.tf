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


resource "aws_s3_bucket_versioning" "state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "state_privacy" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

terraform {
  backend "s3" {
    bucket  = "s3tfstatesafespringboot" # <-- Must match the bucket name above
    key     = "springboot-app/terraform.tfstate"         # <-- The exact path/filename inside S3
    region  = "us-east-1"
    encrypt = true
  }
}

# 3. Define the EC2 Instance resource
resource "aws_instance" "my_web_server" {
  ami           = "ami-0c230065b91270bc6" 
  instance_type = "t2.medium"
  tags = {
    Name = "Terraform-AWSLinux-Server"
  }
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



resource "aws_security_group" "web_traffic" {
  
  vpc_id      = "vpc-00988d7dfb948cf76"
  name        = "allow_web_and_ssh"
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
    Name = "Web-Traffic-SG"
  }
}