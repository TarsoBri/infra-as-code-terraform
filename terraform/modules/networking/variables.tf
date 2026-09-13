variable "env" {
  description = "Environment name (dev or prod) used in resource names and tags"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (1 for dev, 2 for prod)"
  type        = number
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets, one entry per AZ"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets, one entry per AZ"
  type        = list(string)
}
