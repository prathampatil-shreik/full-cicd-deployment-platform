# CI/CD Runbook — full-cicd-deployment-platform

## Architecture Overview

```
Developer push to main/master
        │
        ▼
   GitHub Actions
        │
   ┌────┴────────────────────────────────────────┐
   │  Job 1: validate                            │
   │  • terraform fmt -check                     │
   │  • terraform init / validate / plan         │
   └────┬────────────────────────────────────────┘
        │ (push only)
   ┌────┴────────────────────────────────────────┐
   │  Job 2: build                               │
   │  • Docker build (multi-stage Maven + JRE)   │
   │  • Push :latest + :<sha> to ECR             │
   └────┬────────────────────────────────────────┘
        │
   ┌────┴────────────────────────────────────────┐
   │  Job 3: deploy                              │
   │  • Create new Launch Template version       │
   │    (user-data updated with new image tag)   │
   │  • Start ASG Instance Refresh (rolling)     │
   │  • Poll until Successful / fail on error    │
   └────┬────────────────────────────────────────┘
        │
   ┌────┴────────────────────────────────────────┐
   │  Job 4: verify                              │
   │  • ASG InService count >= 2                 │
   │  • ALB target group healthy targets >= 1    │
   │  • HTTP GET http://<ALB_DNS>/ returns 2xx/3xx│
   │  • ECR image tag confirmed present          │
   └─────────────────────────────────────────────┘
```

Pull requests run the `validate` job only — no build or deploy.

---

## AWS Authentication — IAM User Access Keys

The pipeline authenticates to AWS using a **manually created IAM user** whose
credentials are stored as GitHub Actions repository secrets.

**OIDC is NOT used. No IAM role assumption is performed.**

Every job in the workflow authenticates with:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: ${{ secrets.AWS_REGION }}
```

### Security rules for the IAM user credentials

- **Never commit** `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` to Git.
- **Never hard-code** them in any workflow file, Dockerfile, or Terraform file.
- Store them **only** as GitHub Actions encrypted repository secrets.
- Rotate the access key periodically via the AWS IAM console.
- The IAM user should have only the permissions listed in
  `infrastructure/iam/github-actions-deploy-policy.json` — no `AdministratorAccess`.

---

## Required GitHub Actions Secrets

Set these in:
**GitHub → Repository → Settings → Secrets and variables → Actions → New repository secret**

| Secret name | Value |
|-------------|-------|
| `AWS_ACCESS_KEY_ID` | Access key ID of the IAM user (e.g. `AKIA…`) |
| `AWS_SECRET_ACCESS_KEY` | Secret access key of the IAM user |
| `AWS_REGION` | `us-east-1` |
| `DB_PASSWORD` | RDS master password (used only for `terraform plan`) |

None of these values must ever appear in source code or workflow logs.

---

## IAM User Permissions

The IAM user must have the policy in
`infrastructure/iam/github-actions-deploy-policy.json` attached.

Key permission groups:

| Sid | Purpose |
|-----|---------|
| `ECRAuth` | `ecr:GetAuthorizationToken` — authenticate Docker to ECR |
| `ECRPush` | Push/describe images in the ECR repository |
| `ASGDeploy` | Describe ASG, start/cancel instance refresh |
| `LaunchTemplate` | Create/describe/modify Launch Template versions |
| `ALBVerify` | Describe target groups and target health |
| `TerraformReadInfra` | Read-only describe calls for `terraform plan` |

To attach the policy in the AWS console:

1. Go to **IAM → Users → \<your-user\> → Permissions → Add permissions**.
2. Choose **Attach policies directly → Create policy**.
3. Paste the JSON from `infrastructure/iam/github-actions-deploy-policy.json`.
4. Name it `GitHubActionsDeployPolicy` and attach it to the user.

---

## ECR Image Flow

1. GitHub Actions authenticates to ECR via `aws-actions/amazon-ecr-login` (uses the
   IAM user credentials configured in the previous step).
2. Docker builds the image from `application/Dockerfile`
   (multi-stage: Maven build → JRE runtime).
3. Two tags are pushed:
   - `latest` — always points to the most recent build from main/master.
   - `<full-git-sha>` — immutable, used for the Launch Template user-data update.
4. ECR lifecycle policy retains the 10 most recent images (managed by Terraform).

---

## Deployment Strategy — Rolling Instance Refresh

The pipeline does **not** run `terraform apply`. Instead it:

1. Reads the current Launch Template ID from the ASG.
2. Fetches the current `$Latest` version's user-data (base64-encoded shell script).
3. Decodes it, replaces the ECR image tag with the new commit SHA tag, re-encodes.
4. Creates a new Launch Template version with the updated user-data.
5. Sets that version as the default.
6. Calls `aws autoscaling start-instance-refresh` with `MinHealthyPercentage: 50`.

This means:
- At most 50 % of instances are replaced at a time → zero-downtime.
- New instances boot, pull the new image from ECR via NAT Gateway, start the
  container on port 8080.
- ALB health check (`GET /` → HTTP 200-399) must pass before the old instance
  is drained.
- The pipeline polls every 30 s for up to 20 min; fails the workflow if the
  refresh fails.

The `instance_refresh` block in `modules/compute/main.tf` registers this strategy
with Terraform so future `terraform apply` runs are also rolling.

---

## EC2 / ASG Deployment Mechanism

- ASG: `full-cicd-deployment-platform-dev-app-asg` (desired: 2, min: 2, max: 2)
- Launch Template: `full-cicd-deployment-platform-dev-app-lt`
- Instances are in private subnets; outbound ECR access via NAT Gateway.
- IAM instance profile has `AmazonEC2ContainerRegistryReadOnly` +
  `AmazonSSMManagedInstanceCore`.
- User-data script: logs in to ECR, pulls the image, runs `docker run` with DB
  env vars.

---

## ALB Health Checks

- ALB: `full-cicd-deployment-dev-alb`
- Target Group: `full-cicd-deployment-dev-tg` (port 8080, HTTP)
- Health check path: `GET /` → matcher `200-399`
- Healthy threshold: 2 consecutive checks
- Interval: 30 s, timeout: 5 s

---

## Rollback Procedure

### Option A — Re-run a previous workflow

1. Go to **GitHub → Actions → CI/CD Pipeline**.
2. Find the last successful run.
3. Click **Re-run jobs → Re-run all jobs**.
   This rebuilds and pushes the same commit's image and triggers a new instance
   refresh.

### Option B — Manual ASG instance refresh to a previous LT version

```bash
# List available Launch Template versions
aws ec2 describe-launch-template-versions \
  --launch-template-name full-cicd-deployment-platform-dev-app-lt \
  --query 'LaunchTemplateVersions[*].[VersionNumber,CreateTime]' \
  --output table

# Set a previous version as default
aws ec2 modify-launch-template \
  --launch-template-name full-cicd-deployment-platform-dev-app-lt \
  --default-version <VERSION_NUMBER>

# Trigger a new rolling refresh
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name full-cicd-deployment-platform-dev-app-asg \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":300}'
```

### Option C — Cancel an in-progress refresh

```bash
aws autoscaling cancel-instance-refresh \
  --auto-scaling-group-name full-cicd-deployment-platform-dev-app-asg
```

---

## Triggering the Pipeline

- **Automatic:** push any commit to `main` or `master`.
- **PR validation only:** open a pull request → runs `validate` job only (no deploy).
- **Manual re-deploy:** re-run the workflow from the GitHub Actions UI.

---

## Troubleshooting Failed Deployments

| Symptom | Where to look | Fix |
|---------|--------------|-----|
| `terraform fmt -check` fails | Workflow logs | Run `terraform fmt -recursive` locally and push |
| `terraform validate` fails | Workflow logs | Fix HCL syntax errors |
| Docker build fails | `build` job logs | Check `application/Dockerfile` and `pom.xml` |
| ECR push fails | `build` job logs | Verify `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` secrets and ECR permissions on the IAM user |
| Instance refresh `Failed` | `deploy` job logs | Check EC2 instance system logs via SSM or CloudWatch |
| No healthy ALB targets | `verify` job logs | Connect via SSM: `sudo docker ps`, `sudo docker logs application` |
| HTTP health check fails | `verify` job logs | Check security group rules; verify app started on port 8080 |
| `InvalidClientTokenId` in any job | Workflow logs | The `AWS_ACCESS_KEY_ID` secret is wrong or the key has been deactivated — rotate it in IAM |
| `AccessDenied` in any job | Workflow logs | The IAM user is missing a required permission — check `github-actions-deploy-policy.json` |

### Useful diagnostic commands (run locally with AWS CLI)

```bash
# Check instance refresh status
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name full-cicd-deployment-platform-dev-app-asg

# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names full-cicd-deployment-dev-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)

# Connect to an instance via SSM
aws ssm start-session --target <INSTANCE_ID>
# Then: sudo docker ps && sudo docker logs application
```

---

## Terraform State

Currently the state is stored locally (`terraform.tfstate`). For team use,
migrate to an S3 backend:

```hcl
# infrastructure/terraform/versions.tf  (add backend block)
terraform {
  backend "s3" {
    bucket         = "YOUR-TERRAFORM-STATE-BUCKET"
    key            = "full-cicd-deployment-platform/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "YOUR-TERRAFORM-LOCK-TABLE"
    encrypt        = true
  }
}
```

Until then, `terraform plan` in CI is informational only — it does not apply
changes.
