variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "ubuntu_ami" {
  description = "Ubuntu 22.04 LTS AMI"
  type        = string
  default     = "ami-0fc5d935ebf8bc3bc"
}