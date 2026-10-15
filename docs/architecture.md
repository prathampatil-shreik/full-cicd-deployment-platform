# Architecture Diagram

**Project:** Full CI/CD Deployment Platform — SG/PRJ/DO-02
**Runtime confirmed:** Amazon ECS Fargate (both DEV and PROD)
**Diagram type:** Mermaid (render in GitHub, VS Code with Mermaid extension, or https://mermaid.live)

---

## Full System Architecture

```mermaid
flowchart TD
    subgraph DEV["Developer Workstation"]
        D1[git push to main]
    end

    subgraph GH["GitHub"]
        GH1[GitHub Repository]
        GH2[GitHub Actions Runner]
        GH3[GitHub Environment: prod\nRequired reviewer approval]
    end

    subgraph CICD["CI/CD Pipeline — .github/workflows/ci-cd.yml"]
        J1[Job 1: validate\nterraform fmt / init / validate / plan]
        J2[Job 2: infra-dev\nterraform apply — dev workspace]
        J3[Job 3: build\nDocker build + push to DEV ECR]
        J4[Job 4: deploy-dev\nUpdate DEV ECS service]
        J5[Job 5: verify-dev\nECS count + ALB health + HTTP check]
        J6[Job 6: promote-prod\nSkopeo copy DEV→PROD ECR\nUpdate PROD ECS service]
    end

    subgraph S3B["S3 Backend — eu-north-1"]
        TFS[Terraform State\nfull-cicd-tfstate-284043563957-81d26f3a]
    end

    subgraph ECR["Amazon ECR — eu-north-1"]
        ECRD[DEV ECR\nfull-cicd-deployment-platform-dev-app]
        ECRP[PROD ECR\nfull-cicd-deployment-platform-prod-app]
    end

    subgraph DEVVPC["DEV VPC — 10.0.0.0/16"]
        subgraph PUB_DEV["Public Subnets\n10.0.1.0/24 · 10.0.2.0/24"]
            ALBD[DEV ALB\nfull-cicd-deployment-dev-alb\nHTTP :80]
            IGW_D[Internet Gateway]
        end
        subgraph PRIV_DEV["Private Subnets\n10.0.11.0/24 · 10.0.12.0/24"]
            ECS_D1[ECS Fargate Task 1\nTaskFlow :8080]
            ECS_D2[ECS Fargate Task 2\nTaskFlow :8080]
            RDSD[RDS PostgreSQL DEV\nfull-cicd-deployment-platform-dev-postgres\nport 5432]
            NAT_D[NAT Gateway]
        end
    end

    subgraph PRODVPC["PROD VPC — 10.1.0.0/16"]
        subgraph PUB_PROD["Public Subnets\n10.1.1.0/24 · 10.1.2.0/24"]
            ALBP[PROD ALB\nfull-cicd-deployment-prod-alb\nHTTP :80]
            IGW_P[Internet Gateway]
        end
        subgraph PRIV_PROD["Private Subnets\n10.1.11.0/24 · 10.1.12.0/24"]
            ECS_P1[ECS Fargate Task 1\nTaskFlow :8080]
            ECS_P2[ECS Fargate Task 2\nTaskFlow :8080]
            RDSP[RDS PostgreSQL PROD\nfull-cicd-deployment-platform-prod-postgres\nport 5432]
            NAT_P[NAT Gateway]
        end
    end

    subgraph SHARED["Shared AWS Services — eu-north-1"]
        SM[Secrets Manager\nDB credentials per environment]
        CWD[CloudWatch Dashboard\nfull-cicd-deployment-platform-dashboard]
        CWA[CloudWatch Alarms\nALB 5xx · ECS CPU scale-out/in]
        CWL_D[Log Group\n/ecs/full-cicd-deployment-platform-dev]
        CWL_P[Log Group\n/ecs/full-cicd-deployment-platform-prod]
        SNS[SNS Topic\nfull-cicd-deployment-platform-alerts]
    end

    %% Developer to GitHub
    D1 --> GH1
    GH1 --> GH2

    %% Pipeline flow
    GH2 --> J1
    J1 --> J2
    J2 --> J3
    J3 --> J4
    J4 --> J5
    J5 -.->|manual dispatch\nenvironment=prod| GH3
    GH3 -->|approved| J6

    %% Terraform state
    J2 <--> TFS

    %% Image flow
    J3 --> ECRD
    J6 -->|Skopeo copy\npreserve-digests| ECRP

    %% DEV deploy
    J4 --> ECS_D1
    J4 --> ECS_D2
    ECS_D1 -->|pull image| ECRD
    ECS_D2 -->|pull image| ECRD

    %% PROD deploy
    J6 --> ECS_P1
    J6 --> ECS_P2
    ECS_P1 -->|pull image| ECRP
    ECS_P2 -->|pull image| ECRP

    %% Internet → ALB → ECS
    IGW_D --> ALBD
    ALBD --> ECS_D1
    ALBD --> ECS_D2
    IGW_P --> ALBP
    ALBP --> ECS_P1
    ALBP --> ECS_P2

    %% ECS → RDS
    ECS_D1 --> RDSD
    ECS_D2 --> RDSD
    ECS_P1 --> RDSP
    ECS_P2 --> RDSP

    %% ECS → Secrets Manager
    ECS_D1 --> SM
    ECS_D2 --> SM
    ECS_P1 --> SM
    ECS_P2 --> SM

    %% ECS → NAT (for ECR pull)
    ECS_D1 --> NAT_D
    ECS_D2 --> NAT_D
    ECS_P1 --> NAT_P
    ECS_P2 --> NAT_P

    %% Logging
    ECS_D1 -->|awslogs| CWL_D
    ECS_D2 -->|awslogs| CWL_D
    ECS_P1 -->|awslogs| CWL_P
    ECS_P2 -->|awslogs| CWL_P

    %% Monitoring
    CWA --> SNS
    CWL_D --> CWD
    CWL_P --> CWD
    CWA --> CWD
```

---

## Source-to-Deployment Path

```
git push to main
    │
    ▼
GitHub Actions: validate (terraform fmt/init/validate/plan)
    │
    ▼
GitHub Actions: infra-dev (terraform apply — DEV workspace)
    │
    ▼
GitHub Actions: build
  • docker build application/ (multi-stage: Maven → JRE Alpine)
  • docker push :latest + :<git-sha> → DEV ECR
    │
    ▼
GitHub Actions: deploy-dev
  • aws ecs describe-task-definition (get current)
  • jq: swap container image to new SHA tag
  • aws ecs register-task-definition (new revision)
  • aws ecs update-service (rolling deployment)
  • Poll until rolloutState = COMPLETED
    │
    ▼
GitHub Actions: verify-dev
  • ECS running count >= 2
  • ALB target group healthy >= 2
  • GET /health → HTTP 200
```

---

## Application Request Path

```
User browser / API client
    │  HTTP :80
    ▼
Internet Gateway (public subnet)
    │
    ▼
Application Load Balancer
  • Listener: HTTP :80
  • Target group: full-cicd-deployment-dev-ecs-tg (ip type, port 8080)
  • Health check: GET /health → 200, interval 30s
    │  HTTP :8080 (round-robin)
    ▼
ECS Fargate Task (private subnet, no public IP)
  • Spring Boot TaskFlow application
  • DB credentials injected from Secrets Manager at task start
    │  TCP :5432
    ▼
RDS PostgreSQL (private subnet)
  • Database: appdb
  • Schema: tasks table (JPA-managed via spring.jpa.hibernate.ddl-auto=update)
```

---

## Network Security Boundaries

```
┌─────────────────────────────────────────────────────────────┐
│  PUBLIC (internet-facing)                                   │
│  • ALB security group: inbound HTTP :80 from 0.0.0.0/0     │
│  • ALB security group: outbound all                         │
│  • Internet Gateway attached                                │
│  • Subnets: map_public_ip_on_launch = true                  │
└─────────────────────────────────────────────────────────────┘
                          │ HTTP :8080
┌─────────────────────────────────────────────────────────────┐
│  PRIVATE (application tier)                                 │
│  • ECS task SG: inbound :8080 from ALB SG only              │
│  • ECS task SG: outbound all (for ECR pull via NAT)         │
│  • No public IP on ECS tasks                                │
│  • Subnets: map_public_ip_on_launch = false                 │
│  • Route: 0.0.0.0/0 → NAT Gateway                          │
└─────────────────────────────────────────────────────────────┘
                          │ TCP :5432
┌─────────────────────────────────────────────────────────────┐
│  PRIVATE (database tier)                                    │
│  • RDS SG: inbound :5432 from ECS task SG only              │
│  • RDS SG: inbound :5432 from DEV ECS SG (sg-06fa229574228b45c) │
│  • RDS SG: inbound :5432 from 106.213.81.205/32 (temp rule) │
│  • publicly_accessible = false                              │
│  • Storage encrypted at rest                                │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation vs Target Architecture Gap

| Component | Target | Actual | Notes |
|---|---|---|---|
| Application runtime | ECS Fargate | ECS Fargate ✅ | Confirmed live |
| Load balancer | ALB | ALB ✅ | Both DEV and PROD active |
| Database | RDS PostgreSQL | RDS PostgreSQL ✅ | Both environments available |
| Secrets | Secrets Manager | Secrets Manager ✅ | Injected into ECS tasks |
| Monitoring | CloudWatch | CloudWatch ✅ | Dashboard, alarms, log groups |
| Notifications | SNS | SNS ✅ | Topic exists; email subscription needs confirmation |
| CI/CD | GitHub Actions | GitHub Actions ✅ | 6-job pipeline |
| State backend | S3 | S3 ✅ | Encrypted, S3 native locking |
| EC2 ASG module | Not in target | Exists in `modules/compute/` ⚠️ | Legacy code, not wired into main.tf |
| OIDC auth | Best practice | IAM user keys ⚠️ | Access keys used; OIDC not configured |
| RDS restore verification | Verified data | Instance available, data unverified ⚠️ | Blocked by account EC2 restriction |
| Zero-downtime proof | Measured | Not yet measured ⚠️ | Requires concurrent request test during deploy |
