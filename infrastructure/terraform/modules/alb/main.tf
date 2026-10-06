locals {
  # AWS ALB and target group names are limited to 32 characters.
  name_prefix = substr(var.project_name, 0, 20)
}

resource "aws_lb" "app" {
  name               = "${local.name_prefix}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [var.alb_security_group_id]
  subnets         = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Tier        = "load-balancer"
  }
}

# Legacy EC2 instance target group — kept so existing state is not destroyed.
# The listener forwards to the ECS target group below.
resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-${var.environment}-tg"
  port        = var.target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "8080"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-tg"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Tier        = "application"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ECS Fargate target group.
# target_type = "ip" is required for Fargate ENI-based networking.
# deregistration_delay = 60 replaces the AWS default of 300 s.
# The default 300 s drain time is the primary reason rolling deployments
# exceed the aws ecs wait services-stable 600 s hard limit.
resource "aws_lb_target_group" "ecs" {
  name                 = "${local.name_prefix}-${var.environment}-ecs-tg"
  port                 = var.target_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-ecs-tg"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Tier        = "application"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Listener forwards to the ECS target group.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-http-listener"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
