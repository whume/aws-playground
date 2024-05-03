provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      creator = "terraform"
      repo    = "github.com/whume/aws-playground"
    }
  }
}
