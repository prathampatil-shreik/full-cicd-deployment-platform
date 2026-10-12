# Import blocks for resources that exist in AWS but are absent from Terraform
# state. Terraform 1.10+ processes these automatically during `terraform apply`.
# ALB, target group, listener, RDS instance, and RDS subnet group were deleted
# (they referenced a stale VPC) and will be recreated fresh by Terraform.

import {
  to = module.ecr.aws_ecr_repository.this
  id = "full-cicd-deployment-platform-dev-app"
}

import {
  to = module.ecs.aws_iam_role.ecs_execution
  id = "full-cicd-deployment-platform-dev-ecs-execution-role"
}

import {
  to = module.ecs.aws_iam_role_policy_attachment.ecs_execution_managed
  id = "full-cicd-deployment-platform-dev-ecs-execution-role/arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

import {
  to = module.ecs.aws_cloudwatch_log_group.ecs
  id = "/ecs/full-cicd-deployment-platform-dev"
}

import {
  to = module.ecs.aws_ecs_cluster.this
  id = "full-cicd-deployment-platform-dev"
}
