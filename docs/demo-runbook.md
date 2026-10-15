# Live Demonstration Runbook

**Project:** Full CI/CD Deployment Platform — SG/PRJ/DO-02
**Organization:** Shreik Global
**Runtime:** Amazon ECS Fargate
**Region:** eu-north-1
**Last verified:** October 2026

This runbook is a step-by-step rehearsal guide for the capstone live demonstration.
Work through every stage in order before the actual presentation. Each stage lists
the objective, exact steps, expected output, screenshot number, and recovery advice.

---

## Pre-Demo Checklist

Run these checks before starting the demonstration. Do not begin until all pass.

```powershell
# 1. Confirm DEV application is healthy
curl http://full-cicd-deployment-dev-alb-1324890398.eu-north-1.elb.amazonaws.com/health
# Expected: {"status":"healthy"}

# 2. Confirm PROD application is healthy
curl http://full-cicd-deployment-prod-alb-1332510161.eu-north-1.elb.amazonaws.com/health
# Expected: {"status":"healthy"}

# 3. Confirm DEV ECS service is stable
aws ecs describe-services `
  --cluster full-cicd-deployment-platform-dev `
  --services full-cicd-deployment-platform-dev-app `
  --region eu-north-1 `
  --query "services[0].{Desired:desiredCount,Running:runningCount,Pending:pendingCount}" `
  --output table
# Expected: Desired=2, Running=2, Pending=0

# 4. Confirm AWS CLI is authenticated
aws sts get-caller-identity --output table
# Expected: Account 284043563957

# 5. Confirm Terraform workspace
cd infrastructure\terraform
terraform workspace show
# Expected: dev
```

---

## Stage 1 — Architecture and Repository Walkthrough

**Objective:** Explain what was built, why each component exists, and how they connect.

### Steps

1. Open `docs/architecture.md` and render the Mermaid diagram (use https://mermaid.live or VS Code).
2. Walk through the diagram top to bottom:
   - Developer pushes to GitHub → GitHub Actions triggers automatically
   - Pipeline validates Terraform, applies infrastructure, builds Docker image, deploys to ECS
   - ALB routes internet traffic to ECS Fargate tasks in private subnets
   - ECS tasks read DB credentials from Secrets Manager at startup
   - Tasks connect to RDS PostgreSQL in private subnets
   - CloudWatch collects logs and metrics; SNS sends alarm notifications
3. Open the repository in VS Code or GitHub and show the directory tree.
4. Highlight the separation of concerns:
   - `application/` — Spring Boot app, Dockerfile, tests
   - `infrastructure/terraform/` — all AWS resources as code
   - `.github/workflows/ci-cd.yml` — the entire pipeline in one file
   - `docs/` — runbooks, architecture, evidence

**Expected observation:** Audience understands the end-to-end flow before any live commands run.

**Screenshot:** #26 — Repository structure and architecture diagram side by side.

---

## Stage 2 — Terraform Modules and Infrastructure

**Objective:** Show that all AWS infrastructure is defined as code and reproducible.

### Steps

1. Open `infrastructure/terraform/main.tf` and explain the module wiring:
   - `network` → VPC, subnets, IGW, NAT
   - `security` → security groups for ALB, ECS tasks, RDS
   - `ecr` → container image registry
   - `rds` → PostgreSQL database
   - `alb` → load balancer and target group
   - `ecs` → cluster, task definition, service, IAM role, log group

2. Show `backend.tf` — S3 remote state with encryption and native locking.

3. Show `environments/dev/dev.tfvars` vs `environments/prod/prod.tfvars` — same modules, different values.

4. Run a live Terraform plan to show zero unexpected changes:

```powershell
cd infrastructure\terraform
terraform workspace select dev
$env:TF_VAR_db_password = "<dev-password>"
$env:TF_VAR_db_secret_arn = "arn:aws:secretsmanager:eu-north-1:284043563957:secret:<dev-secret-name>"
terraform plan -var-file="environments/dev/dev.tfvars" -input=false
```

**Expected output:** `Plan: 0 to add, 0 to change, 0 to destroy.`

**Screenshot:** #1 — Terraform plan output showing 0 to destroy.

**Common failure:** Plan shows unexpected changes → check for manual console edits that caused drift. Run `terraform refresh` to reconcile state.

---

## Stage 3 — Push a Harmless Application Change

**Objective:** Trigger the pipeline automatically with a real code change.

### Steps

1. Open `application/src/main/java/com/example/taskflow/controller/ApplicationController.java`.
2. In the `/api/info` endpoint, change the `"message"` value to include a demo timestamp, for example:

```java
"message", "TaskFlow Demo — " + java.time.LocalDate.now()
```

3. Commit and push:

```powershell
git add application/src/main/java/com/example/taskflow/controller/ApplicationController.java
git commit -m "demo: update info message for live demonstration"
git push origin main
```

4. Immediately open **GitHub → Actions** and show the pipeline starting within seconds.

**Expected observation:** The `CI/CD Pipeline` workflow appears with status `In progress`.

**Screenshot:** #8 — GitHub Actions workflow triggered by the push, showing all jobs queued.

**Recovery:** If the push is rejected, check branch protection rules. If the pipeline does not start, verify the `on.push.branches` trigger in `ci-cd.yml` matches your branch name (`main` or `master`).

---

## Stage 4 — Pipeline Walkthrough: Validate and Build

**Objective:** Show each pipeline job running and explain what it does.

### Steps

1. Click into the running workflow in GitHub Actions.
2. Open **Job 1: Validate** and show:
   - `terraform fmt -check` — enforces consistent formatting
   - `terraform init` — downloads providers, connects to S3 backend
   - `terraform validate` — checks HCL syntax
   - `terraform plan` — shows what would change (no apply)

3. Open **Job 2: infra-dev** and show:
   - `terraform apply -auto-approve` — idempotent; 0 changes if infrastructure is current

4. Open **Job 3: build** and show:
   - Multi-stage Docker build: Stage 1 compiles with Maven, Stage 2 copies only the JAR into a minimal JRE Alpine image
   - Two tags pushed: `:latest` and `:<git-sha>`
   - ECR image verification step confirms the push succeeded

**Screenshot:** #8 — All jobs green in the GitHub Actions run.
**Screenshot:** #9 — Build job logs showing Maven test pass and Docker push.

**Common failure:** ECR push fails with `AccessDenied` → verify `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` secrets are set correctly in GitHub repository settings.

---

## Stage 5 — DEV Deployment and Health Verification

**Objective:** Show the ECS rolling deployment and confirm the application is healthy.

### Steps

1. Open **Job 4: deploy-dev** in GitHub Actions and explain:
   - Fetches the current ECS task definition
   - Swaps only the container image tag to the new SHA
   - Registers a new task definition revision
   - Calls `update-service` — ECS starts a rolling replacement
   - Polls every 15 seconds until `rolloutState = COMPLETED`

2. While the deployment runs, show the ECS console:

```powershell
aws ecs describe-services `
  --cluster full-cicd-deployment-platform-dev `
  --services full-cicd-deployment-platform-dev-app `
  --region eu-north-1 `
  --query "services[0].{Desired:desiredCount,Running:runningCount,Pending:pendingCount,Rollout:deployments[0].rolloutState}" `
  --output table
```

3. Show ALB target health during the rollout:

```powershell
aws elbv2 describe-target-health `
  --target-group-arn arn:aws:elasticloadbalancing:eu-north-1:284043563957:targetgroup/full-cicd-deployment-dev-ecs-tg/55f3802508a49a65 `
  --region eu-north-1 `
  --query "TargetHealthDescriptions[*].{IP:Target.Id,Port:Target.Port,State:TargetHealth.State}" `
  --output table
```

4. After deployment completes, open **Job 5: verify-dev** and show:
   - ECS running count check (>= 2)
   - ALB target group healthy count check (>= 2)
   - HTTP GET `/health` → 200

5. Confirm the updated endpoint live:

```powershell
curl http://full-cicd-deployment-dev-alb-1324890398.eu-north-1.elb.amazonaws.com/api/info
```

**Expected output:** JSON with the updated message value from Stage 3.

**Screenshot:** #5 — ECS service showing 2/2 running tasks.
**Screenshot:** #6 — ALB target group showing 2 healthy targets.

**Known issue:** The DEV ECS service deployment record may show `rolloutState: FAILED` even when tasks are running and healthy. This is caused by the account EC2 launch restriction blocking a replacement task during a previous deployment attempt. The application is confirmed healthy via ALB target health and `/health` endpoint. Document this honestly in the evidence.

---

## Stage 6 — CloudWatch Logs

**Objective:** Show that application logs are flowing to CloudWatch from both environments.

### Steps

1. Show DEV logs in the AWS Console:
   - **CloudWatch → Log groups → /ecs/full-cicd-deployment-platform-dev**
   - Click a recent log stream and show Spring Boot startup messages and health check entries.

2. Show the same via CLI:

```powershell
aws logs tail /ecs/full-cicd-deployment-platform-dev `
  --region eu-north-1 `
  --since 30m
```

3. Show PROD logs:

```powershell
aws logs tail /ecs/full-cicd-deployment-platform-prod `
  --region eu-north-1 `
  --since 30m
```

4. Filter for errors to show the search capability:

```powershell
aws logs filter-log-events `
  --log-group-name /ecs/full-cicd-deployment-platform-dev `
  --region eu-north-1 `
  --filter-pattern "ERROR" `
  --start-time ([DateTimeOffset]::UtcNow.AddHours(-1).ToUnixTimeMilliseconds())
```

**Screenshot:** #18 — CloudWatch log events showing actual application log lines.
**Screenshot:** #19 — PROD log group with stored bytes confirming logs are flowing.

---

## Stage 7 — CloudWatch Dashboard and Alarms

**Objective:** Show the monitoring setup and explain what each alarm covers.

### Steps

1. Open the CloudWatch dashboard in the AWS Console:
   - **CloudWatch → Dashboards → full-cicd-deployment-platform-dashboard**

2. Show the three active alarms:

```powershell
aws cloudwatch describe-alarms `
  --region eu-north-1 `
  --query "MetricAlarms[*].{Name:AlarmName,State:StateValue,Metric:MetricName}" `
  --output table
```

   - `full-cicd-dev-alb-5xx-errors` — triggers if HTTP 5xx errors exceed threshold
   - ECS CPU scale-out alarm — triggers when CPU > target, adds tasks
   - ECS CPU scale-in alarm — triggers when CPU < target, removes tasks

3. Show the SNS topic:

```powershell
aws sns list-subscriptions-by-topic `
  --topic-arn arn:aws:sns:eu-north-1:284043563957:full-cicd-deployment-platform-alerts `
  --region eu-north-1 `
  --output json
```

**Screenshot:** #20 — CloudWatch dashboard showing metrics widgets.
**Screenshot:** #21 — CloudWatch alarms list with states.

---

## Stage 8 — PROD Approval and Promotion

**Objective:** Show the manual approval gate and image promotion from DEV to PROD ECR.

### Steps

1. Go to **GitHub → Actions → CI/CD Pipeline → Run workflow**.
2. Set:
   - `image_tag`: `30b871ef445e282e3969715f067d73cbaf34ea65` (the current latest SHA, or the SHA from the demo push)
   - `environment`: `prod`
3. Click **Run workflow**.
4. Show the `promote-prod` job pausing at the `prod` GitHub Environment gate.
5. Click **Review deployments → Approve and deploy**.
6. Show the job steps:
   - Validates the image tag exists in DEV ECR
   - Installs Skopeo
   - Copies image from DEV ECR to PROD ECR with `--preserve-digests`
   - Verifies manifest digest matches
   - Registers new PROD task definition revision
   - Updates PROD ECS service
   - Waits for `rolloutState = COMPLETED`
   - Verifies PROD `/health` → 200

**Screenshot:** #11 — GitHub Actions showing the prod environment approval gate.
**Screenshot:** #13 — PROD health endpoint returning `{"status":"healthy"}` after promotion.

**Common failure:** Digest mismatch → re-run the promote-prod job. If persistent, check Skopeo version and ECR permissions on the IAM user.

---

## Stage 9 — Compare DEV and PROD Image Digests

**Objective:** Prove that DEV and PROD are running images built from the same source commit.

### Steps

```powershell
# DEV latest image digest
aws ecr describe-images `
  --repository-name full-cicd-deployment-platform-dev-app `
  --region eu-north-1 `
  --image-ids imageTag=latest `
  --query "imageDetails[0].{Tags:imageTags,Digest:imageDigest,PushedAt:imagePushedAt}" `
  --output json

# PROD latest promoted image
aws ecr describe-images `
  --repository-name full-cicd-deployment-platform-prod-app `
  --region eu-north-1 `
  --query "sort_by(imageDetails, &imagePushedAt)[-1].{Tags:imageTags,Digest:imageDigest,PushedAt:imagePushedAt}" `
  --output json
```

Explain that the digests differ because they are in separate ECR repositories, but the Skopeo `--preserve-digests` flag ensures the underlying image content is identical. The `prod-<SHA>` tag in PROD ECR directly references the same source commit SHA as the DEV image.

**Screenshot:** #12 — Both ECR describe-images outputs side by side showing matching SHA in the tag.

---

## Stage 10 — Rollback Demonstration

**Objective:** Show that a previous known-good version can be redeployed in minutes.

### Steps

1. Identify the previous image tag:

```powershell
aws ecr describe-images `
  --repository-name full-cicd-deployment-platform-dev-app `
  --region eu-north-1 `
  --query "sort_by(imageDetails, &imagePushedAt)[-10:].{Tags:imageTags,PushedAt:imagePushedAt}" `
  --output table
```

2. Go to **GitHub → Actions → CI/CD Pipeline → Run workflow**.
3. Set:
   - `image_tag`: `da7e4002eb393fdbe03cccad9b8600c56dfb0225` (previous known-good SHA)
   - `environment`: `dev`
4. Click **Run workflow**.
5. Show the deploy-dev job registering a new task definition revision with the old image tag.
6. Confirm the rollback completed:

```powershell
aws ecs describe-services `
  --cluster full-cicd-deployment-platform-dev `
  --services full-cicd-deployment-platform-dev-app `
  --region eu-north-1 `
  --query "services[0].{TaskDef:taskDefinition,Running:runningCount,Rollout:deployments[0].rolloutState}" `
  --output table

curl http://full-cicd-deployment-dev-alb-1324890398.eu-north-1.elb.amazonaws.com/health
```

**Screenshot:** #16 — GitHub Actions workflow_dispatch showing the rollback run completing successfully.

---

## Stage 11 — RDS Backup and Restore Evidence

**Objective:** Show that automated backups are configured and a restore was performed.

### Steps

1. Show backup configuration:

```powershell
aws rds describe-db-instances `
  --db-instance-identifier full-cicd-deployment-platform-dev-postgres `
  --region eu-north-1 `
  --query "DBInstances[0].{BackupRetention:BackupRetentionPeriod,Status:DBInstanceStatus,Encrypted:StorageEncrypted,PubliclyAccessible:PubliclyAccessible}" `
  --output table
```

2. Show available automated backup windows:

```powershell
aws rds describe-db-instance-automated-backups `
  --db-instance-identifier full-cicd-deployment-platform-dev-postgres `
  --region eu-north-1 `
  --query "DBInstanceAutomatedBackups[0].{EarliestRestore:EarliestRestoreTime,LatestRestore:LatestRestoreTime,Retention:BackupRetentionPeriod}" `
  --output table
```

3. Show the restored test instance:

```powershell
aws rds describe-db-instances `
  --db-instance-identifier full-cicd-dev-postgres-restore-test `
  --region eu-north-1 `
  --query "DBInstances[0].{Status:DBInstanceStatus,Engine:Engine,EngineVersion:EngineVersion,Class:DBInstanceClass}" `
  --output table
```

4. State clearly: the restored instance is `available`. Data-level verification (SQL queries confirming the `tasks` table and records) is pending due to an AWS account EC2 launch restriction that prevents bastion access. See `docs/restore-runbook.md` for the pending steps.

**Screenshot:** #22 — RDS automated backup settings showing 7-day retention.
**Screenshot:** #23 — Restored instance `full-cicd-dev-postgres-restore-test` showing `available` status.
**Screenshot:** #24 — PENDING: SQL output confirming restored tables and data.

---

## Stage 12 — Outstanding Items and Honest Assessment

**Objective:** Demonstrate professional transparency about what is complete and what is pending.

Present this table during the demonstration:

| Requirement | Status | Evidence |
|---|---|---|
| ECS Fargate runtime | Complete | ECS service 2/2 running, ALB healthy |
| CI/CD pipeline (6 jobs) | Complete | GitHub Actions workflow runs |
| DEV deployment | Complete | `/health` returns `{"status":"healthy"}` |
| PROD promotion with approval | Complete | PROD ECS service running, rollout COMPLETED |
| Terraform IaC | Complete | All resources managed, S3 backend |
| CloudWatch logs | Complete | Both log groups with stored data |
| CloudWatch alarms | Complete | 3 alarms configured |
| SNS notifications | Complete | Topic exists; email subscription needs confirmation |
| RDS automated backups | Complete | 7-day retention on both instances |
| RDS restore instance | Partial | Instance available; data not yet verified |
| Zero-downtime measurement | Pending | Requires concurrent request test during deploy |
| Autoscaling scale-out evidence | Pending | Requires load test under account restrictions |
| DEV rollout state | Known issue | Shows FAILED due to account block; tasks healthy |

---

## Post-Demo Cleanup Reminder

After the demonstration is complete and all screenshots are captured:

1. Remove the temporary laptop-IP security group rule from the RDS security group.
2. Disable public accessibility on `full-cicd-dev-postgres-restore-test`.
3. Delete `full-cicd-dev-postgres-restore-test` once data verification is complete or no longer needed — it is running on `db.m7g.large` and incurring charges.
4. Delete the temporary bastion security group `sg-0f76b6274c93abb65` after confirming no resources depend on it.
5. See `docs/cleanup-checklist.md` for the full teardown procedure.
