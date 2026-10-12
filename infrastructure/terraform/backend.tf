
terraform {
  backend "s3" {
    bucket       = "full-cicd-tfstate-284043563957-81d26f3a"
    key          = "full-cicd-deployment-platform-new-account/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}
