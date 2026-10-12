# Import blocks for resources that exist in AWS but are absent from Terraform
# state (e.g. after a workspace was recreated or a partial apply failed).
# Terraform 1.10+ processes these automatically during `terraform apply`.
# Safe to leave in place — once imported, subsequent applies are no-ops for
# the import blocks themselves.

import {
  to = module.alb.aws_lb.app
  id = "arn:aws:elasticloadbalancing:eu-north-1:284043563957:loadbalancer/app/full-cicd-deployment-dev-alb/c9f1f1f7634d217e"
}

import {
  to = module.alb.aws_lb_target_group.ecs
  id = "arn:aws:elasticloadbalancing:eu-north-1:284043563957:targetgroup/full-cicd-deployment-dev-ecs-tg/7a076a89ce94d5d8"
}

import {
  to = module.alb.aws_lb_listener.http
  id = "arn:aws:elasticloadbalancing:eu-north-1:284043563957:listener/app/full-cicd-deployment-dev-alb/c9f1f1f7634d217e/f4d167d155ad5be7"
}

import {
  to = module.ecr.aws_ecr_repository.this
  id = "full-cicd-deployment-platform-dev-app"
}

import {
  to = module.rds.aws_db_subnet_group.this
  id = "full-cicd-deployment-platform-dev-db-subnet-group"
}

import {
  to = module.rds.aws_db_instance.this
  id = "db-66PPBQSMH67OHACZP2DAJZWUR4"
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
  id = "arn:aws:ecs:eu-north-1:284043563957:cluster/full-cicd-deployment-platform-dev"
}
