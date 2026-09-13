# Fetch available AZs in the current region dynamically
data "aws_availability_zones" "available" {
  state = "available"
}

# Main VPC — the network boundary for all resources
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${var.env}-vpc" }
}

# Public subnets — only the ALB lives here; exposed to the internet
resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.env}-public-${count.index + 1}" }
}

# Private subnets — ECS tasks, RDS, and ElastiCache live here; no direct internet access
resource "aws_subnet" "private" {
  count             = var.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "${var.env}-private-${count.index + 1}" }
}

# Internet Gateway — allows traffic to flow between the VPC and the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.env}-igw" }
}

# Elastic IP for each NAT Gateway — static public IP required by AWS for NAT
resource "aws_eip" "nat" {
  count  = var.az_count
  domain = "vpc"
  tags   = { Name = "${var.env}-nat-eip-${count.index + 1}" }
}

# NAT Gateway — lets private subnet resources reach the internet (e.g., ECR pulls) without being reachable from it
resource "aws_nat_gateway" "main" {
  count         = var.az_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.env}-nat-${count.index + 1}" }
  depends_on    = [aws_internet_gateway.main]
}

# Route table for public subnets — routes all traffic to the Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.env}-public-rt" }
}

# Associates each public subnet with the public route table
resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route table per private subnet — each routes to its own NAT Gateway
resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
  tags = { Name = "${var.env}-private-rt-${count.index + 1}" }
}

# Associates each private subnet with its corresponding route table
resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security group for the ALB — accepts HTTP and HTTPS from anywhere on the internet
resource "aws_security_group" "alb" {
  name   = "${var.env}-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-alb-sg" }
}

# Security group for ECS tasks — accepts traffic only from the ALB, not the open internet
resource "aws_security_group" "ecs" {
  name   = "${var.env}-ecs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "All traffic from ALB only"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-ecs-sg" }
}

# Security group for RDS — accepts PostgreSQL only from ECS tasks
resource "aws_security_group" "rds" {
  name   = "${var.env}-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from ECS tasks only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-rds-sg" }
}

# Security group for ElastiCache — accepts Redis only from ECS tasks
resource "aws_security_group" "elasticache" {
  name   = "${var.env}-elasticache-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "Redis from ECS tasks only"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-elasticache-sg" }
}
