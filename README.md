# Cross-Cloud Migration: Azure VM → AWS EC2 (AWS MGN)

A hands-on migration project: a real workload running on an Azure VM, migrated to
AWS EC2 using **AWS Application Migration Service (MGN)** — the same rehost
("lift-and-shift") pattern used for on-prem-to-cloud and cloud-to-cloud migrations.

Terraform provisions everything that *can* be automated (the source workload, and
the target networking). The actual replication, test, and cutover steps are
documented here as a real migration runbook, because that's the part of a
migration project that interviewers actually want to hear you walk through.

---

## Why this is structured differently from my other projects

Most infrastructure work is "stand up something new." Migration is different: you're
moving a **live workload** with **minimal downtime** and a **rollback plan** in case
something goes wrong. AWS MGN is agent-based — some steps (installing the replication
agent, triggering cutover) are deliberately manual, because they're supposed to be
deliberate, reviewed actions, not something you'd want fully automated in a script
that could fire without a human checking first.

## The migration framework (the "6 R's")

This project demonstrates a **rehost** — the fastest of the standard cloud migration
strategies:

| Strategy | What it means | Used here? |
|---|---|---|
| **Rehost** | "Lift and shift" — move as-is, minimal changes | ✅ this project |
| Replatform | Move with small optimizations (e.g., swap to managed DB) | — |
| Refactor | Re-architect for cloud-native (e.g., containers, serverless) | — |
| Repurchase | Replace with a SaaS equivalent | — |
| Retain | Leave it where it is | — |
| Retire | Decommission entirely | — |

---

## Architecture

```
   AZURE (source)                                    AWS (target)
┌────────────────────┐                          ┌──────────────────────────┐
│  Source VM          │   MGN Replication Agent  │  Staging subnet          │
│  (nginx workload)    │ ───────────────────────▶ │  (replication servers,   │
│  Ubuntu 22.04        │      continuous CDC       │   managed by MGN)        │
└────────────────────┘                          └───────────┬──────────────┘
                                                              │  test / cutover
                                                              ▼
                                                  ┌──────────────────────────┐
                                                  │  Target subnet           │
                                                  │  (cutover EC2 instance)  │
                                                  └──────────────────────────┘
```

## What this demonstrates

- Understanding and articulating cloud migration strategy (the 6 R's)
- Setting up the networking a migration tool needs before replication can start
- Working with an agent-based, continuously-replicating migration service (MGN)
- Writing a real cutover plan with validation and rollback — not just "click migrate"
- Cross-cloud Terraform (Azure source infra + AWS target infra in one config)

## Tech stack

Terraform · Azure (VM, VNet) · AWS (VPC, EC2, MGN) · AWS Application Migration Service

---

## Prerequisites

- Terraform >= 1.5.0
- Azure CLI authenticated (`az login`)
- AWS CLI authenticated (`aws configure`)
- An SSH key pair (`ssh-keygen` if you don't have one) for the Azure VM

---

## Part 1 — Provision the source and target infrastructure

```bash
git clone https://github.com/JSR-codes/azure-to-aws-vm-migration.git
cd azure-to-aws-vm-migration

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: azure_subscription_id and my_ip are required

terraform init
terraform plan
terraform apply
```

This creates the Azure source VM (running nginx, simulating a real workload) and the
AWS-side VPC/subnets/security groups MGN needs to land replicated data.

## Part 2 — Initialize AWS MGN (one-time, per AWS account/region)

```bash
aws mgn initialize-service --region us-east-1
```

## Part 3 — Install the replication agent on the source VM

SSH into the Azure VM using the `azure_source_vm_public_ip` output, then run the
agent installer (get the current command from the MGN console: **Source servers →
Add source server**, or the [official docs](https://docs.aws.amazon.com/mgn/latest/ug/installing-the-agent.html)):

```bash
ssh azureuser@<azure_source_vm_public_ip>
sudo wget -O ./aws-replication-installer-init.py \
  https://aws-application-migration-service-<region>.s3.<region>.amazonaws.com/latest/linux/aws-replication-installer-init.py
sudo python3 aws-replication-installer-init.py \
  --region <region> \
  --aws-access-key-id <key> \
  --aws-secret-access-key <secret> \
  --no-prompt
```

Once the agent connects, the source server appears in the MGN console and continuous
replication (CDC) into the staging subnet begins automatically.

## Part 4 — Launch a test instance

In the MGN console, once replication reaches 100%: select the source server →
**Launch test instance**. This boots a copy in your AWS target subnet **without**
affecting the still-running Azure source — this is your safety net.

## Part 5 — Validate before cutover

```bash
python3 scripts/validate_migration.py <azure_source_ip> <test_instance_ip>
```

This compares the actual served content between source and target. Don't proceed to
cutover on a MISMATCH — investigate first.

## Part 6 — Cutover

In the MGN console: select the source server → **Launch cutover instance**. This is
the point of no return for this exercise — it's the equivalent of pointing production
traffic at the new instance. In a real migration, this step is where you'd update DNS,
load balancer targets, or connection strings to point at the new AWS instance.

## Part 7 — Decommission the source (only after validating cutover)

Once you've confirmed the cutover instance is healthy and serving correctly for a
reasonable soak period:

```bash
terraform destroy -target=azurerm_linux_virtual_machine.source
```

(Or destroy everything once you're done with the whole exercise — see Cleanup below.)

---

## Rollback plan

If validation fails or something looks wrong post-cutover:
- The Azure source VM is **untouched** until you explicitly destroy it — it keeps
  running as your fallback.
- Point traffic back at the Azure source's IP/DNS.
- Investigate the MGN replication logs and re-attempt cutover once resolved.

This is the actual point of doing a test-instance step before cutover — it's a
deliberate checkpoint, not a formality.

---

## Cleanup

```bash
terraform destroy
```

Also check the MGN console — source servers and their replication/staging resources
in AWS aren't managed by this Terraform config (MGN manages them internally) and
should be disconnected/terminated there once you're done, to avoid ongoing charges.

## Cost notes

- MGN itself is free for the first 90 days per source server, then billed hourly —
  fine for a short demo, but don't leave a source server "replicating" indefinitely.
- The Azure VM and AWS staging/cutover instances bill normally while running.

## Possible extensions

- Automate the agent install step with a startup script triggered by Terraform
  `remote-exec`, using temporary IAM credentials scoped only to MGN
- Add a second source server and migrate a small multi-tier app
- Practice a full failback (AWS → Azure) to demonstrate migration reversibility

## License

MIT
