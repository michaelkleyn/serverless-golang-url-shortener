terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  # Note:  if you update the region, you'll need to update
  #        the Region 'const' values in both lambda functions
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
