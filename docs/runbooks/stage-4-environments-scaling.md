# Stage 4 Runbook — Environments, Zero-Downtime, Scaling

## 1. Environment Overview

| Property | DEV | PROD |
|----------|-----|------|
| Terraform workspace | `default` | `prod` |
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` |
| Public subnets | `10.0.1/2.0/24` | `10.1.1/2.0/24` |
| Private subnets | `10.0.11/12.0/24` | `10.1.11/12.0/24` |
| ALB name | `full-cicd-deployment-dev-alb` | `full-cicd-deployment-prod-alb` |
| Target group | `full-cicd-deployment-dev-tg` | `full-cicd-deployment-prod-tg` |
| ASG name | `full-cicd-deployment-platform-dev-app-asg` | `full-cicd-deployment-platform-prod-app-asg` |
| RDS identifier | `full-cicd-deployment-platform-dev-postgres` | `full-cicd-deployment-platform-prod-postgres` |
| ECR repository | `full-cicd-deployment-platform-dev-app` | **same** (reused) |
| ASG min/desired/max | 2 / 2 / 4 | 2 / 2 / 4 |
| CPU scale target | 60 % | 60 % |

DEV and PROD are completely separate AWS resources managed by separate Terraform
workspace state files. They share one ECR repository so the same image digest
is promoted without rebuilding.

---

## 2. Terraform State Separation

```
infrastructure/terraform/terraform.tfstate          ← DEV (default workspace)
infrastructure/terraform/terraform.tfstate.d/prod/  ← PROD workspace
```

Workspaces ensure DEV and PROD state never overlap.

### Switch workspaces

```bash
cd infrastructure/terraform

# DEV
terraform workspace select default

# PROD
terraform workspace select prod
```

---

## 3. Deploying DEV Infrastructure

```bash
cd infrastructure/terraform
terraform workspace select default
terraform init -input=false
terraform plan  -var-file="terraform.tfvars" -input=false
terraform apply -var-file="terraform.tfvars" -input=false -auto-approve
```

---

## 4. Deploying PROD Infrastructure

`db_password` is never stored in `prod.tfvars`. Pass it via `-var` or environment variable.

```bash
cd infrastructure/terraform
terraform workspace select prod
terraform init -input=false
terraform plan  -var-file="environments/prod/prod.tfvars" \
                -var="db_password=<PROD_PASSWORD>" -input=false
terraform apply -var-file="environments/prod/prod.tfvars" \
                -var="db_password=<PROD_PASSWORD>" -input=false -auto-approve
```

---

## 5. Same-Image Promotion

The CI/CD pipeline builds the Docker image **once** and tags it with the full
Git commit SHA:

```
925213028316.dkr.ecr.us-east-1.amazonaws.com/full-cicd-deployment-platform-dev-app:<sha>
```

DEV is deployed using that SHA tag. After DEV verification passes and a human
approves the `prod` GitHub Actions environment, the **exact same SHA tag** is
written into the PROD Launch Template user-data. No rebuild occurs.

To confirm both environments run the same image:

```bash
# DEV Launch Template user-data (decoded)
aws ec2 describe-launch-template-versions \
  --launch-template-name full-cicd-deployment-platform-dev-app-lt \
  --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' \
  --output text | base64 -d | grep "docker pull"

# PROD Launch Template user-data (decoded)
aws ec2 describe-launch-template-versions \
  --launch-template-name full-cicd-deployment-platform-prod-app-lt \
  --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' \
  --output text | base64 -d | grep "docker pull"
```

Both commands should show the same `<sha>` tag.

---

## 6. Production Approval Process

The `approve-prod` job in the CI/CD pipeline uses the `prod` GitHub Actions
environment. Configure a required reviewer on that environment:

1. Go to **GitHub → Repository → Settings → Environments → prod**.
2. Enable **Required reviewers** and add yourself (or your team).
3. Save.

When a push to `main` triggers the pipeline:
- Jobs 1–4 run automatically (validate → build → deploy-dev → verify-dev).
- Job 5 (`approve-prod`) pauses and sends a review request.
- A reviewer clicks **Review deployments → Approve and deploy** in GitHub Actions.
- Jobs 6–7 (`deploy-prod` → `verify-prod`) then run automatically.

---

## 7. Zero-Downtime Rolling Deployment

Both DEV and PROD use ASG Instance Refresh with:

```
MinHealthyPercentage: 50
InstanceWarmup:       300 seconds
CheckpointPercentages: [50, 100]
CheckpointDelay:       60 seconds
```

This means:
- With 2 instances, 1 is replaced at a time (50 % minimum healthy).
- The new instance must pass ALB health checks before the old one is drained.
- Traffic continues flowing to the healthy old instance during replacement.

The Terraform `instance_refresh` block in `modules/compute/main.tf` also
enforces rolling strategy for any future `terraform apply` that changes the
Launch Template.

### Zero-downtime test

Before triggering a deployment, start a continuous HTTP poll in a separate terminal:

```bash
ALB="full-cicd-deployment-dev-alb-1109505190.us-east-1.elb.amazonaws.com"
while true; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${ALB}/")
  echo "$(date +%T)  HTTP ${CODE}"
  sleep 2
done
```

Push a commit to trigger the pipeline. The HTTP responses should remain 200
throughout the rolling replacement. Any gap longer than ~5 s would indicate
a downtime event.

---

## 8. Auto Scaling Configuration

Both environments use CPU target-tracking:

```hcl
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  policy_type = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_type = "ASGAverageCPUUtilization"
    target_value           = 60   # configurable via cpu_scale_target variable
  }
}
```

ASG limits:

| | DEV | PROD |
|-|-----|------|
| min | 2 | 2 |
| desired | 2 | 2 |
| max | 4 | 4 |

---

## 9. Scale-Out Test

Run a lightweight load test against the DEV ALB to trigger CPU-based scale-out.

```bash
ALB="full-cicd-deployment-dev-alb-1109505190.us-east-1.elb.amazonaws.com"

# Install Apache Bench if not present
sudo apt-get install -y apache2-utils   # Linux
# or: brew install httpd                # macOS

# Send 5000 requests, 50 concurrent — adjust as needed
ab -n 5000 -c 50 "http://${ALB}/"
```

Monitor the ASG while the load runs:

```bash
watch -n 10 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names full-cicd-deployment-platform-dev-app-asg \
  --query "AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:length(Instances)}" \
  --output table'
```

Expected result: desired capacity increases from 2 toward 4 as CPU exceeds 60 %.

After the load stops, the ASG will scale back in (default cooldown ~300 s).

---

## 10. Rollback Procedure

### Option A — Re-run a previous successful pipeline run

1. Go to **GitHub → Actions → CI/CD Pipeline**.
2. Find the last known-good run.
3. Click **Re-run jobs → Re-run all jobs**.

This rebuilds the same commit's image and redeploys it through the same
rolling refresh mechanism.

### Option B — Roll back to a specific previous image tag

```bash
# 1. Find the previous good commit SHA (from ECR or git log)
GOOD_SHA="<previous-commit-sha>"
ECR="925213028316.dkr.ecr.us-east-1.amazonaws.com/full-cicd-deployment-platform-dev-app"
ASG="full-cicd-deployment-platform-dev-app-asg"   # or prod

# 2. Get the current Launch Template ID
LT_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "${ASG}" \
  --query 'AutoScalingGroups[0].LaunchTemplate.LaunchTemplateId' \
  --output text)

# 3. Decode current user-data, swap the image tag, re-encode
USERDATA=$(aws ec2 describe-launch-template-versions \
  --launch-template-id "${LT_ID}" --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' \
  --output text)
DECODED=$(echo "${USERDATA}" | base64 -d)
UPDATED=$(echo "${DECODED}" | sed "s|${ECR}:[^ ]*|${ECR}:${GOOD_SHA}|g")
ENCODED=$(echo "${UPDATED}" | base64 -w 0)

# 4. Create a new LT version and set it as default
NEW_VER=$(aws ec2 create-launch-template-version \
  --launch-template-id "${LT_ID}" \
  --source-version '$Latest' \
  --launch-template-data "{\"UserData\":\"${ENCODED}\"}" \
  --query 'LaunchTemplateVersion.VersionNumber' --output text)

aws ec2 modify-launch-template \
  --launch-template-id "${LT_ID}" \
  --default-version "${NEW_VER}"

# 5. Trigger a rolling refresh
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "${ASG}" \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":300}'
```

### Option C — Cancel an in-progress refresh

```bash
aws autoscaling cancel-instance-refresh \
  --auto-scaling-group-name full-cicd-deployment-platform-dev-app-asg
```

---

## 11. Verification Commands

### DEV

```bash
# ALB DNS
aws elbv2 describe-load-balancers --names full-cicd-deployment-dev-alb \
  --query 'LoadBalancers[0].DNSName' --output text

# Target group health
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names full-cicd-deployment-dev-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)

# ASG state
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names full-cicd-deployment-platform-dev-app-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Instances:Instances[*].{ID:InstanceId,State:LifecycleState,Health:HealthStatus}}'

# Scaling policy
aws autoscaling describe-policies \
  --auto-scaling-group-name full-cicd-deployment-platform-dev-app-asg

# HTTP check
curl -I http://full-cicd-deployment-dev-alb-1109505190.us-east-1.elb.amazonaws.com/
```

### PROD

```bash
# ALB DNS (dynamic after first apply)
aws elbv2 describe-load-balancers --names full-cicd-deployment-prod-alb \
  --query 'LoadBalancers[0].DNSName' --output text

# Target group health
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names full-cicd-deployment-prod-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)

# ASG state
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names full-cicd-deployment-platform-prod-app-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Instances:Instances[*].{ID:InstanceId,State:LifecycleState,Health:HealthStatus}}'
```

---

## 12. Required Evidence / Screenshots

| # | Screenshot | How to capture |
|---|-----------|----------------|
| 1 | DEV application working | Browser: `http://<DEV_ALB_DNS>/` |
| 2 | PROD application working | Browser: `http://<PROD_ALB_DNS>/` |
| 3 | DEV vs PROD config diff | `terraform workspace select default && terraform show` vs `prod` |
| 4 | Same ECR image/digest | `aws ecr describe-images --repository-name full-cicd-deployment-platform-dev-app` showing same SHA tag on both |
| 5 | GitHub Actions DEV deployment | Actions tab → CI/CD Pipeline → deploy-dev job green |
| 6 | GitHub Actions PROD approval | Actions tab → approve-prod job waiting for review |
| 7 | GitHub Actions PROD deployment | Actions tab → deploy-prod + verify-prod jobs green |
| 8 | ALB target health during deployment | AWS Console → EC2 → Target Groups → Targets tab (during refresh) |
| 9 | ASG instance refresh | AWS Console → EC2 → Auto Scaling Groups → Instance refresh tab |
| 10 | Auto scaling policy | AWS Console → EC2 → Auto Scaling Groups → Automatic scaling tab |
| 11 | Scale-out event | `aws autoscaling describe-scaling-activities` or CloudWatch ASG metrics |
| 12 | Rollback | GitHub Actions re-run or AWS CLI rollback commands above |
| 13 | Terraform plan — no unexpected changes | `terraform plan` output showing 0 to destroy for DEV |
