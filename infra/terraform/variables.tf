variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Project name — used in resource tags"
  type        = string
  default     = "mern-todo-app"
}

variable "project_name_short" {
  description = "Short project name — used as a prefix for all resources"
  type        = string
  default     = "mta"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "c7i-flex.large"
}

variable "disk_size_gb" {
  description = "EBS disk size (GB)"
  type        = number
  default     = 30
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key to upload to AWS"
  type        = string
  default     = "/root/mta-tf-key.pub"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for Ansible connection"
  type        = string
  default     = "/root/mta-tf-key.pem"
}
