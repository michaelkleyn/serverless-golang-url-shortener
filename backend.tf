# to make this project more "plug-and-play", the default here
# is to have the terraform state created and stored locally
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# NOTE:  if you would like to instead have your terraform state be stored in an S3 bucket,
#        you'll need to have the bucket created by hand or via terraform and then update the `bucket` field below.
#        The `bucket` field will need to be set to that bucket's name in your AWS account
#terraform {
#  required_version = ">= 1.3.9"
#  backend "s3" {
#    bucket = "terraform-<AWS account ID>-us-east-1"
#    key    = "terraform-url-shortener-test.tfstate"
#    region = "us-east-1"
#  }
#}
