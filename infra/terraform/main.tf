terraform {
  required_version = ">= 0.13"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data source to get the 24.04 Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-20260424"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Data source to get available availability zones in the region
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]   # ignore Local Zone
  }
}


# Choose a Key Pair for SSH access
resource "aws_key_pair" "mta" {
  key_name   = "${var.project_name_short}-tf-key"
  public_key = file(var.ssh_public_key_path)

  tags = {
    Name    = "${var.project_name_short}-key"
    Project = var.project_name
  }
}

# Create VPC
resource "aws_vpc" "mta" {
  cidr_block = "10.10.1.0/24"

  tags = {
    Name    = "${var.project_name_short}-vpc"
    Project = var.project_name
  }
}

# Create Subnet
resource "aws_subnet" "mta" {
  vpc_id            = aws_vpc.mta.id
  availability_zone = data.aws_availability_zones.available.names[0]
  cidr_block        = "10.10.1.0/26"

  tags = {
    Name    = "${var.project_name_short}-public-subnet"
    Project = var.project_name
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "mta" {
  vpc_id = aws_vpc.mta.id

  tags = {
    Name    = "${var.project_name_short}-igw"
    Project = var.project_name
  }
}

# Create a Route Table
resource "aws_route_table" "mta" {
  vpc_id = aws_vpc.mta.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mta.id
  }

  tags = {
    Name    = "${var.project_name_short}-rtb"
    Project = var.project_name
  }
}

# Associate it with the Subnet
resource "aws_route_table_association" "mta" {
  subnet_id      = aws_subnet.mta.id
  route_table_id = aws_route_table.mta.id
}

# Create Security Group for EC2 instances
resource "aws_security_group" "mta" {
  name        = "${var.project_name_short}-sg"
  description = "Allow SSH from specific IP; HTTP, HTTPS, Jenkins, Grafana, Prometheus from everywhere"
  vpc_id      = aws_vpc.mta.id

  # Inbound rules

  # SSH
  ingress {
    description = "SSH from everywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP
  ingress {
    description = "HTTP from everywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS from everywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Jenkins
  ingress {
    description = "Jenkins from everywhere"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Grafana
  ingress {
    description = "Grafana from everywhere"
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus
  ingress {
    description = "Prometheus from everywhere"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound rules

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name_short}-sg"
    Project = var.project_name
  }
}

# Create EC2 Instance
resource "aws_instance" "mta" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.mta.key_name
  subnet_id                   = aws_subnet.mta.id
  vpc_security_group_ids      = [aws_security_group.mta.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.disk_size_gb
    delete_on_termination = true

    tags = {
      Name    = "${var.project_name_short}-disk"
      Project = var.project_name
    }
  }

  # User data script to install Python and pip (for Ansible)
  user_data = <<-EOF
    #!/bin/bash
    
    set -e

    apt update -y
    apt install -y python3 python3-pip

    echo "Bootstrap done" > /tmp/bootstrap.log
  EOF

  tags = {
    Name    = "${var.project_name_short}-server"
    Project = var.project_name
    Env     = "production"
  }
}

# Create inventory file for Ansible
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    server_ip   = aws_instance.mta.public_ip
    project     = var.project_name
    ssh_key     = var.ssh_private_key_path
  })

  filename        = "${path.module}/../ansible/inventory.ini"
  file_permission = "0644"
}
