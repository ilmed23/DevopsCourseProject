provider "aws" {
  access_key = "${var.aws_access_key_id}"
  secret_key = "${var.aws_secret_access_key}"
  region = "${var.aws_region}"
}

#------------------------------ NETWORK AND SECURITY GROUPS-----------------------------------------

# Define a vpc
resource "aws_vpc" "project_vpc" {
  cidr_block = "${var.vpc_cidr}"
  enable_dns_support = true
  enable_dns_hostnames = true
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
  map_public_ip_on_launch = true
  tags = {
    Name = "pruject_vpc_sn1"
  }
}

resource "aws_subnet" "subnet2" {
  vpc_id = "${aws_vpc.project_vpc.id}"
  cidr_block = "${var.subnet2_cidr}"
  availability_zone = "${var.subnet2_az}"
  map_public_ip_on_launch = true
  tags = {
    Name = "pruject_vpc_sn2"
  }
}

resource "aws_subnet" "subnet3" {
  vpc_id = "${aws_vpc.project_vpc.id}"
  cidr_block = "${var.subnet3_cidr}"
  availability_zone = "${var.subnet3_az}"
  map_public_ip_on_launch = true
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

# Security Group
resource "aws_security_group" "project_security_group" {
  name        = "project_security_group"
  description = "Project security group"
  vpc_id      = "${aws_vpc.project_vpc.id}"

  # Allow all traffic within VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${aws_vpc.project_vpc.cidr_block}"]
  }

  # Allow ssh from outside
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Allow Http from outside
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic 
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

# ------------------------------------ IAM ------------------------------------------------------------
resource "aws_iam_policy" "project_iam_policy" {
  name   = "project_policy"
  path   = "/"
  policy = file("${path.module}/iam_policy.json")
}

resource "aws_iam_role" "project_iam_role" {
  name = "project_iam_role"

  assume_role_policy = <<EOF
{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Action": "sts:AssumeRole",
          "Principal": {
            "Service": "ec2.amazonaws.com"
          },
          "Effect": "Allow",
          "Sid": ""
        }
      ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "policy-attach" {
  role       = "${aws_iam_role.project_iam_role.name}"
  policy_arn = "${aws_iam_policy.project_iam_policy.arn}"
}

# An instance profile is required to add the role to ec2 instances
resource "aws_iam_instance_profile" "project_profile" {
  name = "project_iam_role"
  role = "${aws_iam_role.project_iam_role.name}"
}

#---------------------------- ROUTE 53 ----------------------------------------------------------------
resource "aws_route53_zone" "project_hosted_zone" {
  name = "${var.domain_name}"
  vpc {
    vpc_id = "${aws_vpc.project_vpc.id}"
  }
}
#--------------------------- AUTOSCALING GROUPS -------------------------------------------------------
resource "aws_key_pair" "projectKeyPair" {
  key_name   = "FinprojectKeyPair"
  public_key = file("${var.ssh_public_key_path}")
}


#Launch configurations for swarm manager and swarm worker
resource "aws_launch_configuration" "Proj_LC_SwarmManager" {
  name =          "Proj_LC_SwarmManager" 
  image_id      = "${var.aws_ami}"
  instance_type = "${var.ec2_instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.project_profile.name}"
  key_name = "${aws_key_pair.projectKeyPair.key_name}"
  security_groups = ["${aws_security_group.project_security_group.id}"]
  user_data= file("${path.module}/../user_data/UD_SwarmManager.sh")
}

  
resource "aws_launch_configuration" "Proj_LC_SwarmWorker" {
  name =          "Proj_LC_SwarmWorker" 
  image_id      = "${var.aws_ami}"
  instance_type = "${var.ec2_instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.project_profile.name}"
  key_name = "${aws_key_pair.projectKeyPair.key_name}"
  security_groups = ["${aws_security_group.project_security_group.id}"]
  user_data= file("${path.module}/../user_data/UD_SwarmWorker.sh")
}
  # AutoScaling groups
  resource "aws_autoscaling_group" "Proj_ASG_SwarmManagers" {
  name                 = "Proj_ASG_SwarmManagers"
  max_size             = 2
  min_size             = 2
  launch_configuration = "${aws_launch_configuration.Proj_LC_SwarmManager.name}"
  vpc_zone_identifier  = ["${aws_subnet.subnet1.id}", "${aws_subnet.subnet2.id}", "${aws_subnet.subnet3.id}"]

  tags = [
    {
      key                 = "DomainName"
      value               = "${var.domain_name}"
      propagate_at_launch = true
    }
  ]
}

  resource "aws_autoscaling_group" "Proj_ASG_SwarmWorkers" {
  name                 = "Proj_ASG_SwarmWorkers"
  max_size             = 2
  min_size             = 2
  launch_configuration = "${aws_launch_configuration.Proj_LC_SwarmWorker.name}"
  vpc_zone_identifier  = ["${aws_subnet.subnet1.id}", "${aws_subnet.subnet2.id}", "${aws_subnet.subnet3.id}"]

  tags = [
    {
      key                 = "DomainName"
      value               = "${var.domain_name}"
      propagate_at_launch = true
    }
  ]
}