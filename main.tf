terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

locals {
  name = "k8s"
}

# Create VPC
resource "aws_vpc" "vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  tags = {
    Name = "${local.name}-vpc"
  }
}

# import availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Creating public subnet 1
resource "aws_subnet" "public-subnet" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "${local.name}-subnet"
  }
}

# Creating internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${local.name}-igw"
  }
}

# Create elastic ip
resource "aws_eip" "eip" {
  domain = "vpc"
}

# Public Route Table
resource "aws_route_table" "publicRT" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Create Public Subnet Route Table Association PUB01
resource "aws_route_table_association" "public_subnet_rt-ASC01" {
  subnet_id      = aws_subnet.public-subnet.id
  route_table_id = aws_route_table.publicRT.id
}

# Creating keypair RSA key of size 4096 bits
resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Creating private key
resource "local_file" "private-key" {
  content         = tls_private_key.key.private_key_pem
  filename        = "${local.name}-lab-key.pem"
  file_permission = 400
}

# Key pair for SSH access
resource "aws_key_pair" "k8s_key" {
  key_name   = "${local.name}-lab-key"
  public_key = tls_private_key.key.public_key_openssh
}

# Security group for K8s nodes
resource "aws_security_group" "k8s_sg" {
  name        = "${local.name}-lab-sg"
  description = "Security group for Kubernetes lab nodes"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 2379
    to_port   = 2380
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port = 10250
    to_port   = 10259
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-lab-sg"
  }
}

# Ubuntu AMI lookup
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Control Plane Node
resource "aws_instance" "control_plane" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.public-subnet.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.k8s_key.key_name
  iam_instance_profile        = aws_iam_instance_profile.k8s-profile.name
  vpc_security_group_ids      = [aws_security_group.k8s_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = filebase64("${path.module}/control-plane-setup.sh")

  tags = {
    Name = "k8s-control-plane"
    Role = "control-plane"
  }
}

# Worker Node
resource "aws_instance" "worker_node" {
  count                       = 2
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.public-subnet.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.k8s_key.key_name
  iam_instance_profile        = aws_iam_instance_profile.k8s-profile.name
  vpc_security_group_ids      = [aws_security_group.k8s_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = filebase64("${path.module}/worker-node-setup.sh")

  tags = {
    Name = "k8s-worker-node-${count.index + 1}"
    Role = "worker"
  }

  depends_on = [aws_instance.control_plane, time_sleep.wait_120_seconds]
}

# Create s3 bucket for storing join command
resource "aws_s3_bucket" "s3" {
  bucket = "k8sjoin-bucket2"
  force_destroy = true
  tags = {
    Name        = "My-bucket"
    Environment = "Dev"
  }
}

# Create IAM role for ansible
resource "aws_iam_role" "k8s-role" {
  name = "${local.name}-h8s-role-t1"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach S3 full access policy to the role
resource "aws_iam_role_policy_attachment" "s3-policy" {
  role       = aws_iam_role.k8s-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Create IAM instance profile for ansible
resource "aws_iam_instance_profile" "k8s-profile" {
  name = "${local.name}-k8s-profile"
  role = aws_iam_role.k8s-role.name
}

# create time_sleep to wait for instances to be ready
resource "time_sleep" "wait_120_seconds" {
  depends_on = [aws_instance.control_plane]
  create_duration = "120s"
}
