#!/bin/bash

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting application server setup..."

dnf update -y
dnf install -y docker awscli
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

echo "Logging in to Amazon ECR..."

for i in 1 2 3 4 5; do
  aws ecr get-login-password --region ${aws_region} | \
    docker login --username AWS --password-stdin ${ecr_repository_url} && break
  echo "ECR login attempt $i failed, retrying in 10s..."
  sleep 10
done

echo "Pulling application image..."

for i in 1 2 3 4 5; do
  docker pull ${ecr_repository_url}:${container_image_tag} && break
  echo "Pull attempt $i failed, retrying in 10s..."
  sleep 10
done

echo "Starting application container..."

docker rm -f application 2>/dev/null || true

docker run -d \
  --name application \
  --restart unless-stopped \
  -p ${app_port}:${app_port} \
  -e DB_HOST=${db_host} \
  -e DB_PORT=${db_port} \
  -e DB_NAME=${db_name} \
  -e DB_USER=${db_username} \
  -e DB_PASSWORD=${db_password} \
  -e APP_ENV=production \
  -e APP_VERSION=${container_image_tag} \
  ${ecr_repository_url}:${container_image_tag}

echo "Application container started."
docker ps
