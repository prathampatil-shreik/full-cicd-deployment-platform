#!/bin/bash

set -e

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting application server setup..."

dnf update -y

dnf install -y docker awscli

systemctl enable docker
systemctl start docker

usermod -aG docker ec2-user

echo "Logging in to Amazon ECR..."

aws ecr get-login-password --region ${aws_region} | \
  docker login --username AWS --password-stdin ${ecr_repository_url}

echo "Pulling application image..."

docker pull ${ecr_repository_url}:${container_image_tag}

echo "Starting application container..."

docker rm -f application 2>/dev/null || true

docker run -d \
  --name application \
  --restart unless-stopped \
  -p ${app_port}:${app_port} \
  ${ecr_repository_url}:${container_image_tag}

echo "Application container started."

docker ps