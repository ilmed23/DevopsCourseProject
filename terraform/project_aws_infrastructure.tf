provider "aws" {
  access_key = "${var.aws_access_key_id}"
  secret_key = "${var.aws_secret_access_key}"
  region = "${var.aws_region}"
}

# Define a vpc
resource "aws_vpc" "project_vpc" {
  cidr_block = "${var.vpc_cidr}"
  tags = {
    Name = "project_vpc"
  }
}

# Internet gateway
resource "aws_internet_gateway" "project_igw" {
  vpc_id = "${aws_vpc.project_vpc.id}"
  tags = {
    Name = "project_igw"
  }
}

# Private subnet
resource "aws_subnet" "subnet1" {
  vpc_id = "${aws_vpc.project_vpc.id}"
  cidr_block = "${var.subnet1_cidr}"
  availability_zone = "${var.subnet1_az}"
  tags = {
    Name = "pruject_vpc_sn1"
  }
}

resource "aws_subnet" "subnet2" {
  vpc_id = "${aws_vpc.project_vpc.id}"
  cidr_block = "${var.subnet2_cidr}"
  availability_zone = "${var.subnet2_az}"
  tags = {
    Name = "pruject_vpc_sn2"
  }
}

resource "aws_subnet" "subnet3" {
  vpc_id = "${aws_vpc.project_vpc.id}"
  cidr_block = "${var.subnet3_cidr}"
  availability_zone = "${var.subnet3_az}"
  tags = {
    Name = "pruject_vpc_sn3"
  }
}

# Routing table - route all external traffic to igw
resource "aws_route_table" "project_vpc_rt" {
  vpc_id = "${aws_vpc.project_vpc.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.project_igw.id}"
  }
  tags = {
    Name = "project_vpc_rt"
  }
}

# Associate the routing table to all subnets
resource "aws_route_table_association" "subnet1_rt_association" {
  subnet_id = "${aws_subnet.subnet1.id}"
  route_table_id = "${aws_route_table.project_vpc_rt.id}"
}

resource "aws_route_table_association" "subnet2_rt_association" {
  subnet_id = "${aws_subnet.subnet2.id}"
  route_table_id = "${aws_route_table.project_vpc_rt.id}"
}

resource "aws_route_table_association" "subnet3_rt_association" {
  subnet_id = "${aws_subnet.subnet3.id}"
  route_table_id = "${aws_route_table.project_vpc_rt.id}"
}