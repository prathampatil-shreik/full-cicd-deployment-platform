# Stage 4 Runbook — Environments, Zero-Downtime, Scaling

## 1. DEV Architecture

| Resource | Value |
|----------|-------|
| VPC CIDR | `10.0.0.0/16` |
| Public subnets | `10.0.1.0/24`, `10.0.2.0/24` (us-east-1a/b) |
| Private subnets | `10.0.11.0/24`, `10.0.12.0/24` (us-east-1a/b) |
| ALB name | `full-cicd-deployment-dev-alb` |
| ALB DNS | `full-cicd-deployment-dev-alb-1109505190.us-east-1.elb.amazonaws.com` |
| Target group | `full-cicd-deployment-dev-tg` (port 8080, HTTP) |
| ASG name | `full-cicd-deployment-platform-dev-app-asg` |
| Launch template | `full-cicd-deployment-platform-dev-app-lt` |
| RDS identifier | `full-cicd-deployment-platform-dev-postgres` |
| ECR repository | `full-cicd-deployment-platform-dev-app` |
| ASG min/desired/max | 2 / 2 / 4 |
| CPU scale target | 60% |
| Terraform workspace | `default` |
| Terraform state | `infrastructure/terraform/terraform.tfstate` |
| Var file | `infrastructure/terraform/terraform.tfvars` (gitignored) |

## 2. PROD Architecture

| Resource | Value |
|----------|-------|
| VPC CIDR | `10.1.0.0/16` |
| Public subnets | `10.1.1.0/24`, `10.1.2.0/24` (us-east-1a/b) |
| Private subnets | `10.1.11.0/24`, `10.1.12.0/24` (us-east-1a/b) |
| ALB name | `full-cicd-deployment-prod-alb` |
| ALB DNS | Assigned by AWS after first `terraform apply` |
| Target group | `full-cicd-deployment-prod-tg` (port 8080, HTTP) |
| ASG name | `full-cicd-deployment-platform-prod-app-asg` |
| Launch template | `full-cicd-deployment-platform-prod-app-lt` |
| RDS identifier | `full-cicd-deployment-platform-prod-postgres` |
| ECR repository | **same** as DEV — `full-cicd-deployment-platform-dev-app` |
| ASG min/desired/max | 2 / 2 / 4 |
| CPU scale target | 60% |
| Terraform workspace | `prod` |
| Terraform state | `infrastructure/terraform/terraform.tfstate.d/prod/terraform.tfstate` |
| Var file | `infrastructure/terraform/environments/prod/prod.tfvars` (committed, no secrets) |

## 3. DEV vs PROD Configuration Differences

| Property | DEV | PROD |
|----------|-----|------|
| `environment` | `dev` | `prod` |
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` |
| Subnet CIDRs | `10.0.x.0/24` | `10.1.x.0/24` |
| Resource name prefix | `*-dev-*` | `*-prod-*` |
| ECR repo created | yes (by Terraform) | no (reuses DEV repo via `ecr_repository_url_override`) |
| `db_password` source | `terraform.tfvars` (gitignored) | `-var="db_password=..."` at apply time |
| Terraform workspace | `default` | `prod` |
| Deployment approval | automatic | manual (GitHub environment gate) |

**Same across both environments:**

- Docker image and Dockerfile
- Application code
- ECR repository URL
- Immutable image tag (commit SHA)
- All Terraform modules (`network`, `security`, `ecr`, `rds`, `alb`, `compute`)
- ASG instance refresh strategy (Rolling, 50% min healthy, 300s warmup)
- CPU target-tracking scaling policy (60%)
- ALB health check path (`GET /`, matcher `200-399`)

## 4. Same-Image Promotion

The pipeline builds the Docker image **once** per push to `main`:

```
ECR: 925213028316.dkr.ecr.us-east-1.amazonaws.com/full-cicd-deployment-platform-dev-app:<commit-sha>
```

DEV deploys `<commit-sha>`. After DEV verification passes and a reviewer approves
the `prod` GitHub Actions environment, the **exact same `<commit-sha>` tag** is
written into the PROD Launch Template user-data. No rebuild occurs.

To confirm both environments run the same image:

```bash
# DEV Launch Template user-data
aws ec2 describe-launch-template-versions \
  --launch-template-name full-cicd-deployment-platform-dev-app-lt \
  --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' \
  --output text | base64 -d | grep "docker pull"

# PROD Launch Template user-data
aws ec2 describe-launch-template-versions \
  --launch-template-name full-cicd-deployment-platform-prod-app-lt \
  --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' \
  --output text | base64 -d | grep "docker pull"
```

Both commands must show the same `<commit-sha>` tag.

## 5. CI/CD Flow

```
push to main
    │
    ▼
Job 1: validate
  • terraform fmt -check -recursive
  • terraform init / validate / plan (DEV, no apply)
    │
    ▼
Job 2: build
  • docker build (multi-stage Maven → JRE Alpine)
  • push :latest + :<commit-sha> to ECR
  • output: image_tag = <commit-sha>
    │
    ▼
Job 3: deploy-dev
  • read DEV Launch Template ID from ASG
  • create new LT version with image_tag in user-data
  • set new version as default
  • start ASG instance refresh (Rolling, 50% min healthy)
  • poll until Successful
    │
    ▼
Job 4: verify-dev
  • ASG InService count >= 2
  • ALB target group healthy targets >= 1
  • zero-downtime proof: 36 × HTTP polls over 3 min (records pass/fail)
  • final HTTP health check: GET / → 2xx/3xx
  • ECR image tag confirmed present
    │
    ▼
Job 5: approve-prod  ← PAUSES for manual approval
  • uses GitHub Actions environment: prod
  • reviewer clicks "Review deployments → Approve and deploy"
    │
    ▼
Job 6: deploy-prod
  • same mechanism as deploy-dev but targets PROD ASG
  • uses the SAME image_tag from Job 2 (no rebuild)
    │
    ▼
Job 7: verify-prod
  • same checks as verify-dev against PROD resources
  • confirms same image tag as DEV
```

Pull requests run Job 1 only (validate). No build or deploy.

## 6. PROD Approval Process

The `approve-prod` job uses `environment: prod`. GitHub pauses the workflow
at this job until a required reviewer approves.

**One-time setup (repository administrator):**

1. Go to **GitHub → Repository → Settings → Environments**.
2. Click **New environment**, name it `prod`.
3. Enable **Required reviewers**, add yourself or your team.
4. Optionally set **Wait timer** (e.g. 5 minutes) for extra safety.
5. Click **Save protection rules**.

Also create a `dev` environment (no required reviewers needed) so the
`deploy-dev` job can reference it.

**Per-deployment approval:**

When a push to `main` triggers the pipeline and Jobs 1–4 pass:
- Job 5 (`Approve PROD Deployment`) shows as **Waiting** in the Actions UI.
- GitHub sends a notification to required reviewers.
- Reviewer opens the workflow run → clicks **Review deployments** →
  selects `prod` → clicks **Approve and deploy**.
- Jobs 6–7 run automatically.

## 7. Zero-Downtime Deployment

Both DEV and PROD use ASG Instance Refresh with:

```
Strategy:             Rolling
MinHealthyPercentage: 50
InstanceWarmup:       300 seconds
CheckpointPercentages: [50, 100]
CheckpointDelay:       60 seconds
```

With 2 instances and 50% minimum healthy, one instance is replaced at a time:

1. New instance launches with the new Launch Template version.
2. New instance pulls the updated image from ECR via NAT Gateway.
3. Application starts on port 8080.
4. ALB health check (`GET /` → 200-399) passes after 2 consecutive checks.
5. Old instance is deregistered from the ALB and terminated.
6. Process repeats for the second instance.

Traffic continues flowing to the healthy old instance throughout step 1–4.

The `verify-dev` job includes a **zero-downtime proof step** that polls the
DEV ALB every 5 seconds for 3 minutes (36 requests) during/after the refresh
and reports:

```
Zero-downtime result: 36 successful / 0 failed requests
```

Any failures are reported as warnings (the step does not fail the pipeline,
allowing you to capture the evidence).

### Manual zero-downtime test (local)

Start polling before triggering a deployment:

```bash
ALB="full-cicd-deployment-dev-alb-1109505190.us-east-1.elb.amazonaws.com"
while true; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${ALB}/")
  echo "$(date +%T)  HTTP ${CODE}"
  sleep 2
done
```

Push a commit to trigger the pipeline. HTTP responses should remain 200
throughout the rolling replacement.

## 8. ASG Scaling Configuration

Both environments use CPU target-tracking:

```hcl
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  policy_type = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_type = "ASGAverageCPUUtilization"
    target_value           = 60
  }
}
```

| Setting | DEV | PROD |
|---------|-----|------|
| min_size | 2 | 2 |
| desired_capacity | 2 | 2 |
| max_size | 4 | 4 |
| CPU target | 60% | 60% |

AWS automatically adds instances when average CPU exceeds 60% and removes
them when CPU drops back below the target (with a default scale-in cooldown
of ~300 seconds).

## 9. Scale-Out Load Test

Run a lightweight load test against the DEV ALB to trigger CPU-based scale-out.

```bash
ALB="full-cicd-deployment-dev-alb-1109505190.us-east-1.elb.amazonaws.com"

# Option A — Apache Bench (install if needed)
sudo apt-get install -y apache2-utils   # Ubuntu/Debian
# brew install httpd                    # macOS

ab -n 10000 -c 100 "http://${ALB}/"

# Option B — curl loop (no extra tools needed)
for i in $(seq 1 500); do
  curl -s -o /dev/null "http://${ALB}/" &
done
wait
```

Monitor the ASG while the load runs:

```bash
# Poll every 30 seconds
while true; do
  aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names full-cicd-deployment-platform-dev-app-asg \
    --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Count:length(Instances)}' \
    --output table
  sleep 30
done
```

## 10. Expected Scale-Out Behavior

1. Load test starts → CPU on existing 2 instances rises above 60%.
2. After ~3 minutes (CloudWatch alarm evaluation period), AWS triggers scale-out.
3. `DesiredCapacity` increases from 2 toward 4.
4. New instances launch, pull the image, register with the ALB.
5. Load is distributed across 3–4 instances → CPU drops.
6. Load test stops → CPU falls below 60%.
7. After ~5–15 minutes (scale-in cooldown), `DesiredCapacity` returns to 2.

Verify scale-out activity:

```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name full-cicd-deployment-platform-dev-app-asg \
  --query 'Activities[0:5].{Time:StartTime,Cause:Cause,Status:StatusCode}' \
  --output table
```

## 11. Rollback Procedure

### Option A — workflow_dispatch (preferred)

The pipeline supports manual rollback via `workflow_dispatch`:

1. Go to **GitHub → Actions → CI/CD Pipeline → Run workflow**.
2. Fill in:
   - `image_tag`: the previous known-good commit SHA (find it in ECR or `git log`)
   - `environment`: `dev` or `prod`
3. Click **Run workflow**.

For `prod`, the workflow still requires approval from Job 5 before deploying.

Find available image tags in ECR:

```bash
aws ecr describe-images \
  --repository-name full-cicd-deployment-platform-dev-app \
  --query 'sort_by(imageDetails, &imagePushedAt)[-10:].imageTags[0]' \
  --output table
```

### Option B — AWS CLI manual rollback

```bash
GOOD_SHA="<previous-commit-sha>"
ECR="925213028316.dkr.ecr.us-east-1.amazonaws.com/full-cicd-deployment-platform-dev-app"
ASG="full-cicd-deployment-platform-dev-app-asg"   # or prod

LT_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "${ASG}" \
  --query 'AutoScalingGroups[0].LaunchTemplate.LaunchTemplateId' \
  --output text)

USERDATA=$(aws ec2 describe-launch-template-versions \
  --launch-template-id "${LT_ID}" --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' \
  --output text)
DECODED=$(echo "${USERDATA}" | base64 -d)
UPDATED=$(echo "${DECODED}" | sed "s|${ECR}:[^ ]*|${ECR}:${GOOD_SHA}|g")
ENCODED=$(echo "${UPDATED}" | base64 -w 0)

NEW_VER=$(aws ec2 create-launch-template-version \
  --launch-template-id "${LT_ID}" \
  --source-version '$Latest' \
  --launch-template-data "{\"UserData\":\"${ENCODED}\"}" \
  --query 'LaunchTemplateVersion.VersionNumber' --output text)

aws ec2 modify-launch-template \
  --launch-template-id "${LT_ID}" \
  --default-version "${NEW_VER}"

aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "${ASG}" \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":300}'
```

### Option C — Cancel an in-progress refresh

```bash
aws autoscaling cancel-instance-refresh \
  --auto-scaling-group-name full-cicd-deployment-platform-dev-app-asg
```

## 12. Verification Commands

### DEV

```bash
# ALB DNS
aws elbv2 describe-load-balancers --names full-cicd-deployment-dev-alb \
  --query 'LoadBalancers[0].DNSName' --output text

# Target group health
TG_ARN=$(aws elbv2 describe-target-groups \
  --names full-cicd-deployment-dev-tg \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
aws elbv2 describe-target-health --target-group-arn "${TG_ARN}"

# ASG state
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names full-cicd-deployment-platform-dev-app-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:Instances[*].{ID:InstanceId,State:LifecycleState}}'

# Scaling policy
aws autoscaling describe-policies \
  --auto-scaling-group-name full-cicd-deployment-platform-dev-app-asg \
  --query 'ScalingPolicies[*].{Name:PolicyName,Type:PolicyType,Target:TargetTrackingConfiguration.TargetValue}'

# HTTP check
curl -I http://full-cicd-deployment-dev-alb-1109505190.us-east-1.elb.amazonaws.com/

# Current image tag on DEV instances
aws ec2 describe-launch-template-versions \
  --launch-template-name full-cicd-deployment-platform-dev-app-lt \
  --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' \
  --output text | base64 -d | grep "docker pull"
```

### PROD

```bash
# ALB DNS (dynamic after first apply)
aws elbv2 describe-load-balancers --names full-cicd-deployment-prod-alb \
  --query 'LoadBalancers[0].DNSName' --output text

# Target group health
TG_ARN=$(aws elbv2 describe-target-groups \
  --names full-cicd-deployment-prod-tg \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
aws elbv2 describe-target-health --target-group-arn "${TG_ARN}"

# ASG state
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names full-cicd-deployment-platform-prod-app-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:Instances[*].{ID:InstanceId,State:LifecycleState}}'

# Current image tag on PROD instances
aws ec2 describe-launch-template-versions \
  --launch-template-name full-cicd-deployment-platform-prod-app-lt \
  --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' \
  --output text | base64 -d | grep "docker pull"
```

### Terraform

```bash
cd infrastructure/terraform

# DEV
terraform workspace select default
terraform plan -var-file="terraform.tfvars" -input=false

# PROD
terraform workspace select prod
terraform plan -var-file="environments/prod/prod.tfvars" \
               -var="db_password=<PROD_PASSWORD>" -input=false
```

## 13. Evidence / Screenshots to Capture

| # | Evidence | How to capture |
|---|----------|----------------|
| 1 | DEV application working | Browser: `http://<DEV_ALB_DNS>/` |
| 2 | PROD application working | Browser: `http://<PROD_ALB_DNS>/` |
| 3 | Same ECR image tag on DEV and PROD | Run both `grep "docker pull"` commands above — same SHA |
| 4 | GitHub Actions pipeline — all 7 jobs green | Actions tab → CI/CD Pipeline run |
| 5 | GitHub Actions — approve-prod waiting | Actions tab → Job 5 showing "Waiting" state |
| 6 | GitHub Actions — approval dialog | "Review deployments" modal with `prod` environment |
| 7 | DEV ASG instance refresh | AWS Console → EC2 → Auto Scaling Groups → `dev-app-asg` → Instance refresh tab |
| 8 | PROD ASG instance refresh | Same for `prod-app-asg` |
| 9 | ALB target health during refresh | AWS Console → EC2 → Target Groups → Targets tab (capture mid-refresh) |
| 10 | Zero-downtime proof | `verify-dev` job logs showing "36 successful / 0 failed requests" |
| 11 | Auto scaling policy | AWS Console → EC2 → Auto Scaling Groups → Automatic scaling tab |
| 12 | Scale-out event | `aws autoscaling describe-scaling-activities` output showing DesiredCapacity increase |
| 13 | Scale-in recovery | Same command after load stops showing DesiredCapacity return to 2 |
| 14 | Rollback via workflow_dispatch | Actions tab → "Run workflow" dialog with image_tag input |
| 15 | Terraform plan — 0 to destroy for DEV | Terminal output of `terraform plan` on default workspace |
