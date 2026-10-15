# Full CI/CD Deployment Platform

**Project Reference:** SG/PRJ/DO-02
**Organization:** Shreik Global
**AWS Region:** `eu-north-1`
**Repository:** https://github.com/prathampatil-shreik/full-cicd-deployment-platform

A production-grade CI/CD platform that automatically builds, tests, and deploys a Spring Boot task-management application (TaskFlow) to AWS ECS Fargate across separate DEV and PROD environments using Terraform, Docker, and GitHub Actions.

---

## Architecture Overview

```
Developer (git push to main)
        │
        ▼
  GitHub Actions CI/CD Pipeline
        │
  ┌─────┴──────────────────────────────────────────────┐
  │  Job 1: validate                                   │
  │  • terraform fmt / init / validate / plan (dev)    │
  └─────┬──────────────────────────────────────────────┘
        │ (push to main only)
  ┌─────┴──────────────────────────────────────────────┐
  │  Job 2: infra-dev                                  │
  │  • terraform apply (dev workspace)                 │
  └─────┬──────────────────────────────────────────────┘
        │
  ┌─────┴──────────────────────────────────────────────┐
  │  Job 3: build                                      │
  │  • Docker multi-stage build (Maven → JRE Alpine)   │
  │  • Push :latest + :<git-sha> to DEV ECR            │
  └─────┬──────────────────────────────────────────────┘
        │
  ┌─────┴──────────────────────────────────────────────┐
  │  Job 4: deploy-dev                                 │
  │  • Register new ECS task definition revision       │
  │  • Update DEV ECS service (rolling deployment)     │
  │  • Wait for COMPLETED rollout state                │
  └─────┬──────────────────────────────────────────────┘
        │
  ┌─────┴──────────────────────────────────────────────┐
  │  Job 5: verify-dev                                 │
  │  • ECS running count >= 2                          │
  │  • ALB target group healthy targets >= 2           │
  │  • GET /health → HTTP 200                          │
  └─────┬──────────────────────────────────────────────┘
        │ (manual workflow_dispatch, environment=prod)
  ┌─────┴──────────────────────────────────────────────┐
  │  Job 6: promote-prod  [requires GitHub approval]   │
  │  • Verify image tag exists in DEV ECR              │
  │  • Copy image to PROD ECR via Skopeo               │
  │  • Verify manifest digest matches                  │
  │  • Update PROD ECS service                         │
  │  • Wait for COMPLETED rollout state                │
  │  • Verify PROD /health → HTTP 200                  │
  └────────────────────────────────────────────────────┘
```

### Request path (runtime)

```
Internet → ALB (public subnets) → ECS Fargate tasks (private subnets)
                                         │
                                         ▼
                              RDS PostgreSQL (private subnets)
                              Secrets Manager (DB credentials)
```

See `docs/architecture.md` for the full Mermaid diagram.

---

## Technology Stack

| Layer | Technology |
|---|---|
| Application | Java 17, Spring Boot 3.2.5, Spring Data JPA |
| Database | Amazon RDS PostgreSQL 16.15 |
| Container | Docker (multi-stage), Amazon ECR |
| Runtime | Amazon ECS Fargate |
| Load balancing | Application Load Balancer (HTTP/80) |
| Infrastructure as Code | Terraform >= 1.10, AWS provider ~> 6.0 |
| CI/CD | GitHub Actions |
| Secrets | AWS Secrets Manager |
| Monitoring | CloudWatch Logs, CloudWatch Alarms, CloudWatch Dashboard |
| Notifications | Amazon SNS |
| State backend | S3 (encrypted, with S3 native locking) |

---

## Repository Structure

```
full-cicd-deployment-platform/
├── .github/
│   └── workflows/
│       └── ci-cd.yml                  # Single pipeline: validate → build → deploy-dev → verify-dev → promote-prod
├── application/
│   ├── src/
│   │   ├── main/
│   │   │   ├── java/com/example/taskflow/
│   │   │   │   ├── config/            # ApplicationConfig, CorsConfig
│   │   │   │   ├── controller/        # ApplicationController (/health, /api/info, /version)
│   │   │   │   │                      # TaskController (CRUD /api/tasks)
│   │   │   │   ├── exception/         # GlobalExceptionHandler, TaskNotFoundException
│   │   │   │   ├── model/             # Task entity, TaskStatus enum, TaskPriority enum
│   │   │   │   ├── repository/        # TaskRepository (Spring Data JPA)
│   │   │   │   ├── service/           # TaskService
│   │   │   │   └── TaskFlowApplication.java
│   │   │   └── resources/
│   │   │       └── application.properties
│   │   └── test/
│   │       └── java/com/example/taskflow/
│   │           └── TaskFlowApplicationTests.java
│   ├── Dockerfile                     # Multi-stage: Maven build → eclipse-temurin:17-jre-alpine
│   ├── docker-compose.yml             # Local dev with PostgreSQL
│   └── pom.xml                        # Spring Boot 3.2.5, JPA, PostgreSQL, H2 (test)
├── docs/
│   ├── architecture.md                # Mermaid architecture diagram
│   ├── evidence-checklist.md          # Screenshot evidence requirements
│   ├── demo-runbook.md                # Live demonstration procedure
│   ├── restore-runbook.md             # RDS backup and restore procedure
│   ├── cleanup-checklist.md           # Safe teardown checklist
│   └── runbooks/
│       ├── cicd-runbook.md            # Legacy EC2/ASG runbook (superseded by ECS)
│       ├── stage-4-runbook.md         # Legacy Stage 4 runbook (superseded)
│       └── stage-4-environments-scaling.md  # Legacy scaling runbook (superseded)
├── infrastructure/
│   ├── iam/
│   │   ├── github-actions-deploy-policy.json  # IAM policy for GitHub Actions user
│   │   └── github-oidc-trust-policy.json      # OIDC trust policy (not currently used)
│   └── terraform/
│       ├── environments/
│       │   ├── dev/
│       │   │   └── dev.tfvars         # DEV variable values (no secrets)
│       │   └── prod/
│       │       └── prod.tfvars        # PROD variable values (no secrets)
│       ├── modules/
│       │   ├── alb/                   # ALB, target group, HTTP listener
│       │   ├── compute/               # EC2 Launch Template + ASG (legacy, not active runtime)
│       │   ├── ecr/                   # ECR repository + lifecycle policy
│       │   ├── ecs/                   # ECS cluster, task definition, service, IAM, log group
│       │   ├── network/               # VPC, subnets, IGW, NAT, route tables
│       │   ├── rds/                   # RDS PostgreSQL instance + subnet group
│       │   └── security/              # Security groups: ALB, app, ECS task, RDS
│       ├── main.tf                    # Root module: wires all child modules
│       ├── variables.tf               # All input variable declarations
│       ├── outputs.tf                 # Key outputs: ALB DNS, ECR URL, ECS names, log group
│       ├── versions.tf                # Terraform >= 1.10, AWS provider ~> 6.0
│       ├── backend.tf                 # S3 backend (encrypted, S3 native locking)
│       ├── terraform.tfvars           # DEV defaults (no secrets; gitignored pattern exception)
│       └── .terraform.lock.hcl        # Provider version lock file (committed)
├── .gitignore
├── prod-db-secret.json                # SENSITIVE — gitignored, must not be committed
└── task-test.json                     # SENSITIVE — gitignored, must not be committed
```

### Key file purposes

| Path | Purpose | Phase |
|---|---|---|
| `.github/workflows/ci-cd.yml` | Full pipeline: 6 jobs, push + PR + manual dispatch | 2–5 |
| `application/Dockerfile` | Multi-stage build: Maven compile → minimal JRE runtime | 2 |
| `application/pom.xml` | Spring Boot 3.2.5 dependencies, Maven build config | 1 |
| `application/src/.../ApplicationController.java` | `/health` endpoint (DB connectivity check), `/api/info`, `/version` | 1 |
| `application/src/.../Task.java` | JPA entity mapped to `tasks` table in PostgreSQL | 1 |
| `infrastructure/terraform/main.tf` | Wires network → security → ecr → rds → alb → ecs modules | 3 |
| `infrastructure/terraform/backend.tf` | S3 remote state, encrypted, S3 native locking | 3 |
| `infrastructure/terraform/modules/ecs/main.tf` | ECS cluster, Fargate task definition, service, IAM role, log group | 4 |
| `infrastructure/terraform/modules/network/main.tf` | VPC, 2 public + 2 private subnets, IGW, NAT, route tables | 3 |
| `infrastructure/terraform/modules/rds/main.tf` | RDS PostgreSQL, private subnet group, encrypted storage | 3 |
| `infrastructure/terraform/modules/compute/main.tf` | Legacy EC2 ASG module — exists in code but not wired in main.tf | — |
| `infrastructure/iam/github-actions-deploy-policy.json` | Least-privilege IAM policy for the GitHub Actions IAM user | 2 |
| `docs/architecture.md` | Mermaid source for architecture diagram | 6 |
| `docs/restore-runbook.md` | RDS point-in-time restore procedure | 5 |
| `docs/cleanup-checklist.md` | Safe resource teardown checklist | 6 |

---

## Prerequisites

- AWS CLI v2 configured with credentials for account `284043563957`
- Terraform >= 1.10
- Docker Desktop (for local builds)
- Java 17 + Maven 3.9 (for local application builds)
- `psql` client (for database verification)
- PowerShell 7+ (Windows) or bash (Linux/macOS)

---

## AWS Environment Layout

| Property | DEV | PROD |
|---|---|---|
| Terraform workspace | `dev` | `prod` |
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` |
| Public subnets | `10.0.1.0/24`, `10.0.2.0/24` | `10.1.1.0/24`, `10.1.2.0/24` |
| Private subnets | `10.0.11.0/24`, `10.0.12.0/24` | `10.1.11.0/24`, `10.1.12.0/24` |
| ALB DNS | `full-cicd-deployment-dev-alb-1324890398.eu-north-1.elb.amazonaws.com` | `full-cicd-deployment-prod-alb-1332510161.eu-north-1.elb.amazonaws.com` |
| ECS cluster | `full-cicd-deployment-platform-dev` | `full-cicd-deployment-platform-prod` |
| ECS service | `full-cicd-deployment-platform-dev-app` | `full-cicd-deployment-platform-prod-app` |
| ECR repository | `full-cicd-deployment-platform-dev-app` | `full-cicd-deployment-platform-prod-app` |
| RDS identifier | `full-cicd-deployment-platform-dev-postgres` | `full-cicd-deployment-platform-prod-postgres` |
| CloudWatch log group | `/ecs/full-cicd-deployment-platform-dev` | `/ecs/full-cicd-deployment-platform-prod` |
| ECS desired count | 2 | 2 |

---

## Terraform Setup

### Initialize

```powershell
cd infrastructure\terraform
terraform init -input=false
```

### Select workspace

```powershell
# DEV
terraform workspace select dev

# PROD
terraform workspace select prod
```

### Format and validate

```powershell
terraform fmt -check -recursive
terraform validate
```

### Plan

```powershell
# DEV
$env:TF_VAR_db_password = "<dev-password>"
$env:TF_VAR_db_secret_arn = "arn:aws:secretsmanager:eu-north-1:284043563957:secret:<dev-secret-name>"
terraform plan -var-file="environments/dev/dev.tfvars" -input=false

# PROD
$env:TF_VAR_db_password = "<prod-password>"
$env:TF_VAR_db_secret_arn = "arn:aws:secretsmanager:eu-north-1:284043563957:secret:<prod-secret-name>"
terraform plan -var-file="environments/prod/prod.tfvars" -input=false
```

### Apply

```powershell
# DEV
terraform workspace select dev
terraform apply -var-file="environments/dev/dev.tfvars" -input=false -auto-approve

# PROD — requires explicit approval; never use -auto-approve in production
terraform workspace select prod
terraform apply -var-file="environments/prod/prod.tfvars" -input=false
```

### Key outputs

```powershell
terraform output alb_dns_name
terraform output ecr_repository_url
terraform output ecs_cluster_name
terraform output ecs_service_name
terraform output ecs_log_group_name
```

---

## Application — Local Build and Test

```powershell
cd application
mvn clean test
mvn clean package -DskipTests
```

Run locally with Docker Compose (requires a local PostgreSQL):

```powershell
docker compose up --build
curl http://localhost:8080/health
```

---

## Docker Image Build and ECR Publication

```powershell
$REGION   = "eu-north-1"
$ACCOUNT  = "284043563957"
$REPO     = "full-cicd-deployment-platform-dev-app"
$TAG      = git rev-parse HEAD

# Authenticate
aws ecr get-login-password --region $REGION |
  docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

# Build
docker build -t "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPO}:${TAG}" application/

# Push
docker push "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/${REPO}:${TAG}"
```

---

## GitHub Actions Pipeline

The pipeline is defined in `.github/workflows/ci-cd.yml` and has six jobs:

| Job | Trigger | Purpose |
|---|---|---|
| `validate` | push, PR, dispatch | `terraform fmt`, `init`, `validate`, `plan` |
| `infra-dev` | push, dev dispatch | `terraform apply` for DEV workspace |
| `build` | push only | Docker build + push `:latest` and `:<sha>` to DEV ECR |
| `deploy-dev` | push + dev dispatch | Register new ECS task def revision, update DEV service |
| `verify-dev` | after deploy-dev | ECS count, ALB target health, `/health` HTTP check |
| `promote-prod` | prod dispatch only | Copy image DEV→PROD ECR via Skopeo, update PROD ECS |

Pull requests run `validate` only — no build or deploy.

### Required GitHub Actions secrets

Set these at: **GitHub → Repository → Settings → Secrets and variables → Actions**

| Secret name | Purpose |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key ID |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret access key |
| `DB_PASSWORD` | RDS master password (used by `terraform plan/apply`) |
| `DB_SECRET_ARN` | Secrets Manager ARN for DB credentials (used by ECS task) |

Secret values must never appear in source code, workflow logs, or Terraform files.

---

## DEV Deployment and Health Verification

```powershell
# Check ECS service status
aws ecs describe-services `
  --cluster full-cicd-deployment-platform-dev `
  --services full-cicd-deployment-platform-dev-app `
  --region eu-north-1 `
  --query "services[0].{Status:status,Desired:desiredCount,Running:runningCount,Rollout:deployments[0].rolloutState}" `
  --output table

# Check ALB target health
aws elbv2 describe-target-health `
  --target-group-arn arn:aws:elasticloadbalancing:eu-north-1:284043563957:targetgroup/full-cicd-deployment-dev-ecs-tg/55f3802508a49a65 `
  --region eu-north-1 `
  --query "TargetHealthDescriptions[*].{IP:Target.Id,Port:Target.Port,State:TargetHealth.State}" `
  --output table

# HTTP health check
curl http://full-cicd-deployment-dev-alb-1324890398.eu-north-1.elb.amazonaws.com/health
```

Expected response: `{"status":"healthy"}`

---

## PROD Approval and Promotion

PROD deployments are triggered manually via `workflow_dispatch` with `environment=prod`.

1. Go to **GitHub → Actions → CI/CD Pipeline → Run workflow**
2. Set `image_tag` to the DEV commit SHA to promote
3. Set `environment` to `prod`
4. Click **Run workflow**
5. When the `promote-prod` job reaches the `prod` GitHub Environment gate, a required reviewer must approve

The pipeline copies the image from DEV ECR to PROD ECR using Skopeo with `--preserve-digests`, verifies the manifest digest matches, then updates the PROD ECS service.

---

## Comparing DEV and PROD Image Digests

```powershell
# DEV — latest image digest
aws ecr describe-images `
  --repository-name full-cicd-deployment-platform-dev-app `
  --region eu-north-1 `
  --image-ids imageTag=latest `
  --query "imageDetails[0].imageDigest" --output text

# PROD — current image digest
aws ecr describe-images `
  --repository-name full-cicd-deployment-platform-prod-app `
  --region eu-north-1 `
  --query "sort_by(imageDetails, &imagePushedAt)[-1].imageDigest" --output text
```

The digests will differ because DEV and PROD use separate ECR repositories. The pipeline verifies digest integrity during promotion using Skopeo manifest comparison.

---

## ECS Troubleshooting

```powershell
# List running tasks
aws ecs list-tasks `
  --cluster full-cicd-deployment-platform-dev `
  --region eu-north-1

# Describe a specific task
aws ecs describe-tasks `
  --cluster full-cicd-deployment-platform-dev `
  --tasks <task-arn> `
  --region eu-north-1 `
  --query "tasks[0].{Status:lastStatus,Health:healthStatus,StoppedReason:stoppedReason,Containers:containers[*].{Name:name,Status:lastStatus,Reason:reason}}"

# View recent ECS service events
aws ecs describe-services `
  --cluster full-cicd-deployment-platform-dev `
  --services full-cicd-deployment-platform-dev-app `
  --region eu-north-1 `
  --query "services[0].events[:10][].message"
```

---

## CloudWatch Logs

```powershell
# Tail DEV application logs (last 50 events)
aws logs tail /ecs/full-cicd-deployment-platform-dev `
  --region eu-north-1 `
  --follow

# Filter for errors
aws logs filter-log-events `
  --log-group-name /ecs/full-cicd-deployment-platform-dev `
  --region eu-north-1 `
  --filter-pattern "ERROR"
```

Log groups:
- DEV: `/ecs/full-cicd-deployment-platform-dev` (7-day retention, ~704 KB stored)
- PROD: `/ecs/full-cicd-deployment-platform-prod` (7-day retention, ~97 KB stored)

---

## CloudWatch Alarms and Dashboard

Active alarms:

| Alarm | Metric | Current State |
|---|---|---|
| `full-cicd-dev-alb-5xx-errors` | `HTTPCode_Target_5XX_Count` | INSUFFICIENT_DATA |
| ECS CPU scale-out (auto-created) | `CPUUtilization` | OK |
| ECS CPU scale-in (auto-created) | `CPUUtilization` | ALARM |

Dashboard: `full-cicd-deployment-platform-dashboard`

View in AWS Console: **CloudWatch → Dashboards → full-cicd-deployment-platform-dashboard**

---

## SNS Notifications

Topic ARN: `arn:aws:sns:eu-north-1:284043563957:full-cicd-deployment-platform-alerts`

To add an email subscription:

```powershell
aws sns subscribe `
  --topic-arn arn:aws:sns:eu-north-1:284043563957:full-cicd-deployment-platform-alerts `
  --protocol email `
  --notification-endpoint your@email.com `
  --region eu-north-1
```

Confirm the subscription by clicking the link in the confirmation email.

---

## RDS Automated Backups

Both DEV and PROD RDS instances have automated backups enabled with a 7-day retention period.

```powershell
# List available automated backups for DEV
aws rds describe-db-instance-automated-backups `
  --db-instance-identifier full-cicd-deployment-platform-dev-postgres `
  --region eu-north-1 `
  --query "DBInstanceAutomatedBackups[0].{EarliestRestoreTime:EarliestRestoreTime,LatestRestoreTime:LatestRestoreTime,RetentionPeriod:BackupRetentionPeriod}"
```

For the full restore procedure, see `docs/restore-runbook.md`.

**Current restore test status:** The restored instance `full-cicd-dev-postgres-restore-test` is `available` but data contents have not been verified due to an AWS account EC2 launch restriction. See `docs/restore-runbook.md` for the pending verification steps.

---

## Rollback Procedure

To roll back DEV or PROD to a previous image:

1. Go to **GitHub → Actions → CI/CD Pipeline → Run workflow**
2. Set `image_tag` to the previous known-good commit SHA
3. Set `environment` to `dev` or `prod`
4. Click **Run workflow**

Find available image tags:

```powershell
aws ecr describe-images `
  --repository-name full-cicd-deployment-platform-dev-app `
  --region eu-north-1 `
  --query "sort_by(imageDetails, &imagePushedAt)[-10:].imageTags" `
  --output table
```

---

## Cleanup

See `docs/cleanup-checklist.md` for the full safe teardown procedure.

Quick reference — destroy DEV infrastructure:

```powershell
cd infrastructure\terraform
terraform workspace select dev
terraform destroy -var-file="environments/dev/dev.tfvars" -input=false
```

Always capture all required screenshots and complete the demo before running destroy.

---

## Security Notes

- Database credentials are stored in AWS Secrets Manager and injected into ECS tasks at runtime — never in environment variables baked into images
- The `db_password` Terraform variable is marked `sensitive = true`
- RDS instances are in private subnets with `publicly_accessible = false`
- ECS tasks run in private subnets with no public IP
- The GitHub Actions IAM user has a least-privilege policy in `infrastructure/iam/github-actions-deploy-policy.json`
- Authentication uses IAM user access keys stored as GitHub Actions encrypted secrets — OIDC is not currently configured
- ECR repositories have `scan_on_push = true`
- RDS storage is encrypted at rest (`storage_encrypted = true`)

---

## Known Limitations and Outstanding Items

| Item | Status |
|---|---|
| DEV ECS latest deployment rollout state | `FAILED` — tasks are running and healthy but the deployment record shows FAILED. Investigate via ECS service events. |
| RDS restore data verification | Pending — AWS account EC2 launch restriction prevents bastion access. Resolve account verification to complete. |
| Restore test instance `full-cicd-dev-postgres-restore-test` | Still running on `db.m7g.large` — incurring charges. Delete after verification or account block resolution. |
| Legacy `modules/compute/` | EC2 ASG module exists in code but is not wired into `main.tf`. The active runtime is ECS Fargate. |
| Legacy runbooks in `docs/runbooks/` | Describe EC2/ASG deployment — superseded by the current ECS Fargate pipeline. |
| Zero-downtime measurement | Not yet formally measured with a concurrent request test during a live deployment. |
| Autoscaling scale-out evidence | Not yet captured under load. |
| SNS email confirmation | Subscription must be confirmed by clicking the email link. |

---

## Troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| `terraform fmt -check` fails in CI | Workflow logs | Run `terraform fmt -recursive` locally and push |
| ECS tasks not starting | ECS service events, CloudWatch logs | Check Secrets Manager ARN, security group rules, task definition |
| ALB targets unhealthy | Target group health, `/health` endpoint | Verify DB connectivity; check RDS security group allows ECS task SG |
| ECR push fails | GitHub Actions build job | Verify `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` secrets |
| `AccessDenied` in pipeline | Any job logs | Check IAM policy in `infrastructure/iam/github-actions-deploy-policy.json` |
| PROD promote fails digest mismatch | promote-prod job logs | Re-run; if persistent, check Skopeo version and ECR permissions |
