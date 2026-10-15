# Cleanup Checklist

**Project:** Full CI/CD Deployment Platform — SG/PRJ/DO-02
**Organization:** Shreik Global
**Region:** eu-north-1

> **STOP.** Do not begin teardown until every item in the Pre-Teardown Gate is confirmed.
> Destroying infrastructure before capturing evidence cannot be undone.

---

## Pre-Teardown Gate

Complete every item before running any destructive command.

- [ ] All required screenshots captured (see `docs/evidence-checklist.md`)
- [ ] Live demonstration completed or explicitly approved for teardown
- [ ] Project report submitted or saved locally
- [ ] `docs/restore-runbook.md` data verification complete (or waived with justification)
- [ ] Terraform state backed up: `terraform show > terraform-state-snapshot.txt`
- [ ] Git repository pushed to GitHub with all documentation committed

---

## Phase 1 — Temporary Resources (Safe to Remove Now)

These resources were created for the RDS restore test and are not managed by Terraform. Remove them first.

### 1.1 Restored RDS test instance

> Cost: ~$0.26/hour on `db.m7g.large`. Remove as soon as data verification is done.

```powershell
# Confirm this is the test instance, not the production database
aws rds describe-db-instances `
  --db-instance-identifier full-cicd-dev-postgres-restore-test `
  --region eu-north-1 `
  --query "DBInstances[0].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass}" `
  --output table

# Delete (no final snapshot needed — this is a restore test copy)
aws rds delete-db-instance `
  --db-instance-identifier full-cicd-dev-postgres-restore-test `
  --skip-final-snapshot `
  --region eu-north-1

aws rds wait db-instance-deleted `
  --db-instance-identifier full-cicd-dev-postgres-restore-test `
  --region eu-north-1
Write-Host "Restore test instance deleted"
```

### 1.2 Temporary security group rules on the RDS security group

```powershell
# Remove laptop IP rule
aws ec2 revoke-security-group-ingress `
  --group-id sg-016c666b07a9b956f `
  --protocol tcp --port 5432 `
  --cidr 106.213.81.205/32 `
  --region eu-north-1

# Remove bastion SG rule
aws ec2 revoke-security-group-ingress `
  --group-id sg-016c666b07a9b956f `
  --protocol tcp --port 5432 `
  --source-group sg-0f76b6274c93abb65 `
  --region eu-north-1
```

### 1.3 Temporary bastion security group

```powershell
# Only run after confirming no EC2 instances use this SG
aws ec2 describe-instances `
  --filters "Name=instance.group-id,Values=sg-0f76b6274c93abb65" `
  --region eu-north-1 `
  --query "Reservations[*].Instances[*].InstanceId" --output text
# Expected: empty output

aws ec2 delete-security-group `
  --group-id sg-0f76b6274c93abb65 `
  --region eu-north-1
```

### 1.4 Unused DB subnet group

```powershell
# This was created during the failed subnet group swap attempt
aws rds delete-db-subnet-group `
  --db-subnet-group-name full-cicd-restore-public-subnet-group `
  --region eu-north-1
```

---

## Phase 2 — Terraform-Managed Infrastructure

Terraform manages all core infrastructure. Use `terraform destroy` to remove it cleanly.
Never manually delete Terraform-managed resources — this causes state drift.

### 2.1 Pre-destroy checks

```powershell
cd infrastructure\terraform

# Confirm you are on the correct workspace before destroying
terraform workspace show

# Review what will be destroyed — read this output carefully
$env:TF_VAR_db_password = "<dev-password>"
$env:TF_VAR_db_secret_arn = "arn:aws:secretsmanager:eu-north-1:284043563957:secret:<dev-secret-name>"
terraform plan -destroy -var-file="environments/dev/dev.tfvars" -input=false
```

Look for any resource marked `# will be destroyed` that you did not expect. Do not proceed if the plan shows unexpected resources.

### 2.2 Destroy DEV infrastructure

```powershell
terraform workspace select dev
terraform destroy -var-file="environments/dev/dev.tfvars" -input=false
```

Type `yes` when prompted. Do not use `-auto-approve` for destroy operations.

Monitor the destroy output. Terraform destroys resources in dependency order:
ECS service → ECS cluster → ALB → RDS → security groups → subnets → VPC → ECR → IAM roles

### 2.3 Destroy PROD infrastructure

```powershell
terraform workspace select prod
$env:TF_VAR_db_password = "<prod-password>"
$env:TF_VAR_db_secret_arn = "arn:aws:secretsmanager:eu-north-1:284043563957:secret:<prod-secret-name>"
terraform destroy -var-file="environments/prod/prod.tfvars" -input=false
```

Type `yes` when prompted.

---

## Phase 3 — Post-Destroy Verification

Run these checks after `terraform destroy` completes to confirm no billable resources remain.

### 3.1 ECS

```powershell
aws ecs list-clusters --region eu-north-1 --output json
# Expected: {"clusterArns": []}
```

### 3.2 ALB and target groups

```powershell
aws elbv2 describe-load-balancers --region eu-north-1 `
  --query "LoadBalancers[*].{Name:LoadBalancerName,State:State.Code}" --output table
# Expected: empty table

aws elbv2 describe-target-groups --region eu-north-1 `
  --query "TargetGroups[*].TargetGroupName" --output table
# Expected: empty table
```

### 3.3 RDS instances

```powershell
aws rds describe-db-instances --region eu-north-1 `
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Status:DBInstanceStatus}" --output table
# Expected: empty table (all instances deleted)
```

### 3.4 ECR repositories

```powershell
aws ecr describe-repositories --region eu-north-1 `
  --query "repositories[*].repositoryName" --output table
# Expected: empty (or confirm you intentionally retained images)
```

If you want to retain images for evidence before deleting the repository:

```powershell
# Delete all images first, then the repository
aws ecr batch-delete-image `
  --repository-name full-cicd-deployment-platform-dev-app `
  --region eu-north-1 `
  --image-ids imageTag=latest

aws ecr delete-repository `
  --repository-name full-cicd-deployment-platform-dev-app `
  --region eu-north-1 `
  --force
```

### 3.5 NAT Gateways and Elastic IPs

NAT Gateways are destroyed by `terraform destroy`. Verify no orphaned EIPs remain:

```powershell
aws ec2 describe-addresses --region eu-north-1 `
  --query "Addresses[*].{AllocationId:AllocationId,AssociationId:AssociationId,PublicIp:PublicIp}" `
  --output table
# Expected: empty or only EIPs you intentionally retain
```

Release any unassociated EIPs to stop charges:

```powershell
aws ec2 release-address --allocation-id <allocation-id> --region eu-north-1
```

### 3.6 CloudWatch log groups

Log groups are Terraform-managed and destroyed with the infrastructure. Verify:

```powershell
aws logs describe-log-groups --region eu-north-1 `
  --log-group-name-prefix "/ecs/full-cicd" `
  --query "logGroups[*].{Name:logGroupName,StoredBytes:storedBytes}" --output table
# Expected: empty
```

### 3.7 CloudWatch alarms and dashboard

```powershell
aws cloudwatch describe-alarms --region eu-north-1 `
  --query "MetricAlarms[*].AlarmName" --output table

aws cloudwatch list-dashboards --region eu-north-1 `
  --query "DashboardEntries[*].DashboardName" --output table
```

If alarms or the dashboard were created outside Terraform, delete them manually:

```powershell
aws cloudwatch delete-alarms `
  --alarm-names "full-cicd-dev-alb-5xx-errors" `
  --region eu-north-1

aws cloudwatch delete-dashboards `
  --dashboard-names "full-cicd-deployment-platform-dashboard" `
  --region eu-north-1
```

### 3.8 SNS topic

```powershell
aws sns list-topics --region eu-north-1 --output json
```

If the topic was created outside Terraform:

```powershell
aws sns delete-topic `
  --topic-arn arn:aws:sns:eu-north-1:284043563957:full-cicd-deployment-platform-alerts `
  --region eu-north-1
```

### 3.9 Secrets Manager

The DB credential secrets were created manually before Terraform was run. They are not destroyed by `terraform destroy`. Delete them manually after teardown:

```powershell
# List secrets
aws secretsmanager list-secrets --region eu-north-1 `
  --query "SecretList[?contains(Name,'full-cicd')].{Name:Name,ARN:ARN}" --output table

# Schedule deletion (7-day recovery window; use --force-delete-without-recovery to skip)
aws secretsmanager delete-secret `
  --secret-id "full-cicd-deployment-platform/dev/database" `
  --recovery-window-in-days 7 `
  --region eu-north-1
```

### 3.10 S3 Terraform state bucket

The S3 backend bucket is not managed by Terraform (it must exist before Terraform runs). Do not delete it until you are certain you will never need to recover state.

```powershell
# List objects in the state bucket
aws s3 ls s3://full-cicd-tfstate-284043563957-81d26f3a --recursive
```

To delete the bucket after all state is no longer needed:

```powershell
# Empty the bucket first
aws s3 rm s3://full-cicd-tfstate-284043563957-81d26f3a --recursive

# Then delete the bucket
aws s3 rb s3://full-cicd-tfstate-284043563957-81d26f3a
```

---

## Phase 4 — Intentionally Retained Resources

Document any resources you are keeping after teardown and why.

| Resource | Reason to Retain | Monthly Cost |
|---|---|---|
| S3 state bucket | May need state for reference | ~$0.023/GB |
| ECR images (if retained) | Evidence for report | ~$0.10/GB |
| RDS automated backup snapshots | Evidence; expire after 7 days automatically | $0 after instance deleted |

---

## Phase 5 — Final Cost Check

After all cleanup, run a final cost check:

```powershell
# Check for any running EC2 instances
aws ec2 describe-instances `
  --filters "Name=instance-state-name,Values=running" `
  --region eu-north-1 `
  --query "Reservations[*].Instances[*].{ID:InstanceId,Type:InstanceType,Name:Tags[?Key=='Name']|[0].Value}" `
  --output table

# Check for any running RDS instances
aws rds describe-db-instances --region eu-north-1 `
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass}" `
  --output table

# Check for NAT Gateways (expensive: ~$0.045/hour each)
aws ec2 describe-nat-gateways `
  --filter "Name=state,Values=available" `
  --region eu-north-1 `
  --query "NatGateways[*].{ID:NatGatewayId,State:State,VPC:VpcId}" `
  --output table

# Check for ALBs (~$0.008/hour each)
aws elbv2 describe-load-balancers --region eu-north-1 `
  --query "LoadBalancers[*].{Name:LoadBalancerName,State:State.Code}" --output table
```

All tables should be empty after a complete teardown.
