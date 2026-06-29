variable "region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "techstream"
}

variable "allowed_cidr" {
  description = "CIDR block allowed to reach SSH and Flask port 5000"
  default     = "10.0.0.0/8"
}
