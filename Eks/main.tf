terraform {
  backend "s3" {
    bucket = "test-t-bucket"
    key    = "terraform.tfstate"
    region = "us-east-1" 
  }
}