variable "aws_access_key_id" {
  description = "AWS access key"
}

variable "aws_secret_access_key" {
  description = "AWS secret access key"
}
variable "aws_region" {
  description = "AWS region"
}

variable "aws_ami" {
  description = "ami to be used for ec2 instances"
}

variable "vpc_cidr" {
  description = "Uber IP addressing for demo Network"
}
variable "subnet1_az" {
  description = "availability zone used for subnet 1"
}

variable "subnet2_az" {
  description = "availability zone used for subnet 2"
}

variable "subnet3_az" {
  description = "availability zone used for subnet 3"
}

variable "subnet1_cidr" {
  description = "Private CIDR block for subnet 1"
}
variable "subnet2_cidr" {
  description = "Private CIDR block for subnet 2"
}
variable "subnet3_cidr" {
  description = "Private CIDR block for subnet 3"
}

variable "domain_name" {
  description = "Domain name for private hosted zone"
}