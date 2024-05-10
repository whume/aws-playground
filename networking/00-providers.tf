provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      creator = "terraform"
      repo    = "github.com/whume/aws-playground"
      stack   = "networking"
    }
  }
}

terraform {
  backend "s3" {
    bucket = "tf-state-176207359176"
    key    = "networking/terraform.tfstate"
    region = "us-east-1"
  }
}