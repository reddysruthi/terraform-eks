# Configure the AWS Provider
provider "aws" {
  region = var.region
  #profile = "test-demo"
}

terraform {
  required_version = ">= 1.0"

  required_providers {
     aws = {
      source  = "hashicorp/aws"
      version = "~> 4.9"
    }
  }
}