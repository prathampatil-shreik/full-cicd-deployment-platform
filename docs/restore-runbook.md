# RDS Restore Runbook

**Project:** Full CI/CD Deployment Platform — SG/PRJ/DO-02
**Organization:** Shreik Global
**Region:** eu-north-1
**Source database:** `full-cicd-deployment-platform-dev-postgres`
**Restored test instance:** `full-cicd-dev-postgres-restore-test`

---

## Current Restore Status

| Step | Status | Notes |
|---|---|---|
| Identify source database and backup window | Complete | 7-day retention, backups confirmed |
| Restore to separate test instance | Complete | Instance `available` on `db.m7g.large` |
| Configure public accessibility | Complete | `PubliclyAccessible=true` set |
| Add security group rule for laptop IP | Complete | `106.213.81.205/32` → port 5432 |
| Network connectivity from laptop | Blocked | RDS is in private subnets; no IGW route |
| Bastion EC2 for SSH tunnel | Blocked | AWS account EC2 launch restriction active |
| SQL verification of restored data | Pending | Cannot connect until account block resolved |
| Cleanup of test instance | Pending | Delete after data verification |

**The restored instance is available and structurally correct. Data-level verification is pending due to an AWS account verification block that prevents launching EC2 instances. Resolve the block via AWS Support before completing this runbook.**

---

## Part 1 — Identify the Source Database and Recovery Points

```powershell
# Confirm source database is available
aws rds describe-db-instances `
  --db-instance-identifier full-cicd-deployment-platform-dev-postgres `
  --region eu-north-1 `
  --query "DBInstances[0].{Status:DBInstanceStatus,Engine:Engine,EngineVersion:EngineVersion,BackupRetention:BackupRetentionPeriod,Encrypted:StorageEncrypted}" `
  --output table

# Check available restore window
aws rds describe-db-instance-automated-backups `
  --db-instance-identifier full-cicd-deployment-platform-dev-postgres `
  --region eu-north-1 `
  --query "DBInstanceAutomatedBackups[0].{EarliestRestore:EarliestRestoreTime,LatestRestore:LatestRestoreTime,Retention:BackupRetentionPeriod,Status:Status}" `
  --output table
```

**Expected:** Status `retained` or `active`, retention 7 days, restore window spanning the last 7 days.

---

## Part 2 — Restore to a Separate Test Instance

The restore was already performed. The command used was:

```powershell
aws rds restore-db-instance-to-point-in-time `
  --source-db-instance-identifier full-cicd-deployment-platform-dev-postgres `
  --target-db-instance-identifier full-cicd-dev-postgres-restore-test `
  --restore-time <ISO-8601-timestamp> `
  --db-instance-class db.t3.micro `
  --no-publicly-accessible `
  --region eu-north-1
```

> Note: The restored instance was created as `db.m7g.large` (the default class selected by AWS during restore). This is more expensive than `db.t3.micro`. After verification, delete the instance to stop charges.

### Confirm the restored instance is available

```powershell
aws rds describe-db-instances `
  --db-instance-identifier full-cicd-dev-postgres-restore-test `
  --region eu-north-1 `
  --query "DBInstances[0].{Status:DBInstanceStatus,Class:DBInstanceClass,Engine:Engine,EngineVersion:EngineVersion,PubliclyAccessible:PubliclyAccessible,Endpoint:Endpoint.Address}" `
  --output table
```

**Expected:** Status `available`, endpoint `full-cicd-dev-postgres-restore-test.cx66w6cii2tf.eu-north-1.rds.amazonaws.com`.

---

## Part 3 — Network Connectivity Requirements

The restored instance is in private subnets (`10.0.11.0/24`, `10.0.12.0/24`) with a route table that routes outbound traffic through a NAT Gateway — not an Internet Gateway. Even with `PubliclyAccessible=true`, inbound connections from the internet cannot reach the instance because the subnet has no IGW route.

**The only safe connection method is an SSH tunnel through a bastion EC2 instance in a public subnet.**

### Why direct connection fails

| Check | Result |
|---|---|
| `PubliclyAccessible` | `true` — RDS has a public IP |
| DNS resolves to | `13.51.164.240` — a real public IP |
| Subnet route table | `0.0.0.0/0 → nat-0c1da2aa1cf68ff8c` — NAT only, no IGW |
| Subnet type | Private — `MapPublicIpOnLaunch=false` |
| Result | Inbound TCP 5432 from internet is unreachable |

### Why subnet group swap fails

AWS does not allow moving an RDS instance between subnet groups within the same VPC. The error `InvalidVPCNetworkStateFault` is returned regardless of AZ coverage.

### Required: Bastion EC2 in public subnet

Once the AWS account EC2 launch restriction is resolved, launch a temporary bastion:

```powershell
# Create bastion security group (one-time)
$BASTION_SG = "sg-0f76b6274c93abb65"   # already created

# Launch bastion in public subnet eu-north-1b
aws ec2 run-instances `
  --image-id ami-0baea243788bd0868 `
  --instance-type t3.nano `
  --key-name databaseCheck `
  --subnet-id subnet-05a6d43befc8889a1 `
  --security-group-ids $BASTION_SG `
  --associate-public-ip-address `
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=temp-rds-bastion}]" `
  --region eu-north-1 `
  --query "Instances[0].InstanceId" --output text
```

Wait for the instance to reach `running` state:

```powershell
$BASTION_ID = "<instance-id-from-above>"
aws ec2 wait instance-running --instance-ids $BASTION_ID --region eu-north-1

$BASTION_IP = aws ec2 describe-instances `
  --instance-ids $BASTION_ID `
  --region eu-north-1 `
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text
```

---

## Part 4 — Connect via SSH Tunnel

Open a **separate PowerShell window** and run the tunnel. Leave it open.

```powershell
$KEY_PATH = "C:\Users\<YourName>\databaseCheck.pem"
$RDS_HOST = "full-cicd-dev-postgres-restore-test.cx66w6cii2tf.eu-north-1.rds.amazonaws.com"

# Fix key permissions first (Windows requirement)
icacls $KEY_PATH /inheritance:r /grant:r "$($env:USERNAME):(R)"

# Open tunnel: local port 15432 → RDS port 5432 via bastion
ssh -i $KEY_PATH `
    -L 15432:${RDS_HOST}:5432 `
    -N -o StrictHostKeyChecking=accept-new `
    ec2-user@$BASTION_IP
```

The terminal will appear to hang — this is correct. The tunnel is active.

### Test the tunnel in a second PowerShell window

```powershell
Test-NetConnection -ComputerName 127.0.0.1 -Port 15432
```

**Expected:** `TcpTestSucceeded : True`

Only proceed to psql after this test passes.

---

## Part 5 — Connect with psql

Retrieve the database password from Secrets Manager (do not store it in a variable or script):

```powershell
aws secretsmanager get-secret-value `
  --secret-id "full-cicd-deployment-platform/dev/database" `
  --region eu-north-1 `
  --query "SecretString" --output text
```

Copy the password value from the output. Then connect — the `-W` flag prompts for the password securely:

```powershell
psql -h 127.0.0.1 -p 15432 -U appadmin -d appdb -W
```

Paste the password when prompted. Do not type it into a script or command line argument.

---

## Part 6 — Verify the Restored Data

Run these queries after connecting. Do not invent table names — discover them first.

```sql
-- Confirm you are connected to the correct database and user
SELECT current_database(), current_user, version();
```

**Expected:** `current_database = appdb`, `current_user = appadmin`, PostgreSQL 16.15.

```sql
-- Discover all application tables (excludes system schemas)
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_type = 'BASE TABLE'
  AND table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY table_schema, table_name;
```

**Expected:** At minimum a `tasks` table in the `public` schema (created by Spring Boot JPA on first application startup).

```sql
-- Count rows in the tasks table
SELECT COUNT(*) AS total_tasks FROM tasks;

-- Inspect a sample of records
SELECT id, title, status, priority, created_at
FROM tasks
ORDER BY created_at DESC
LIMIT 10;
```

**Record the results.** Compare the row count and most recent `created_at` timestamp against the restore point time to confirm the restore captured the expected data.

```sql
-- Confirm the restore point (latest record timestamp vs restore time)
SELECT MAX(created_at) AS latest_record FROM tasks;
```

If the latest record timestamp is before the restore point time, the restore is consistent.

---

## Part 7 — Record Recovery Metrics

After completing the SQL verification, record:

| Metric | Value |
|---|---|
| Restore point time | `<ISO timestamp used in restore command>` |
| Instance available time | `<timestamp when status became available>` |
| Recovery Time Objective (RTO) | `<available time minus restore start time>` |
| Latest record in restored DB | `<MAX(created_at) from tasks>` |
| Row count in tasks table | `<COUNT(*) result>` |
| Data verification result | Pass / Fail / Partial |

---

## Part 8 — Cleanup After Verification

Run these steps in order after data verification is complete.

### 1. Exit psql and close the SSH tunnel

```
\q
```

Then press `Ctrl+C` in the tunnel window.

### 2. Terminate the bastion instance

```powershell
aws ec2 terminate-instances --instance-ids $BASTION_ID --region eu-north-1
aws ec2 wait instance-terminated --instance-ids $BASTION_ID --region eu-north-1
```

### 3. Remove the bastion SG rule from the RDS security group

```powershell
aws ec2 revoke-security-group-ingress `
  --group-id sg-016c666b07a9b956f `
  --protocol tcp --port 5432 `
  --source-group sg-0f76b6274c93abb65 `
  --region eu-north-1
```

### 4. Remove the laptop IP rule from the RDS security group

```powershell
aws ec2 revoke-security-group-ingress `
  --group-id sg-016c666b07a9b956f `
  --protocol tcp --port 5432 `
  --cidr 106.213.81.205/32 `
  --region eu-north-1
```

### 5. Delete the bastion security group

```powershell
aws ec2 delete-security-group --group-id sg-0f76b6274c93abb65 --region eu-north-1
```

### 6. Disable public accessibility on the restored instance

```powershell
aws rds modify-db-instance `
  --db-instance-identifier full-cicd-dev-postgres-restore-test `
  --no-publicly-accessible `
  --apply-immediately `
  --region eu-north-1
```

### 7. Delete the restored test instance

Only run this after data verification is complete and all screenshots are captured.

```powershell
aws rds delete-db-instance `
  --db-instance-identifier full-cicd-dev-postgres-restore-test `
  --skip-final-snapshot `
  --region eu-north-1
```

Wait for deletion:

```powershell
aws rds wait db-instance-deleted `
  --db-instance-identifier full-cicd-dev-postgres-restore-test `
  --region eu-north-1
```

### 8. Confirm the original database is untouched

```powershell
aws rds describe-db-instances `
  --db-instance-identifier full-cicd-deployment-platform-dev-postgres `
  --region eu-north-1 `
  --query "DBInstances[0].{Status:DBInstanceStatus,PubliclyAccessible:PubliclyAccessible,BackupRetention:BackupRetentionPeriod}" `
  --output table
```

**Expected:** Status `available`, `PubliclyAccessible=false`, `BackupRetentionPeriod=7`.

---

## Cost Warning

The restored instance `full-cicd-dev-postgres-restore-test` is running on `db.m7g.large` in `eu-north-1`. Approximate cost: **~$0.26/hour**. Delete it as soon as data verification is complete.

The temporary bastion `t3.nano` costs ~$0.0047/hour and should be terminated immediately after the tunnel session ends.
