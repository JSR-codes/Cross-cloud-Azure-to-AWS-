# Cross-Cloud Migration: Azure VM → AWS EC2 (AWS MGN)

This is a real migration, not just infra standup. I had a workload running on an
Azure VM and moved it to AWS EC2 using AWS Application Migration Service (MGN) -
basically the "lift and shift" pattern you'd use for an on-prem-to-cloud or
cloud-to-cloud move.

Terraform handles the parts that make sense to automate: the source VM and the
target-side networking. The replication, testing, and cutover steps I left as a
manual runbook below, because that's genuinely how you'd want to run a real
migration - and it's also the part people actually ask about in interviews, not
the Terraform.

## Why this looks different from a normal "spin up infra" repo

Most of my other projects are "build something new." This one isn't. You're
moving a live workload, you want minimal downtime, and you need a way back out if
something breaks. MGN is agent-based, and a few steps here (installing the agent,
triggering cutover) are manual on purpose - those are the moments you want a
person looking at the screen, not a script firing on its own.

## Which migration strategy is this (the "6 R's")

This is a rehost - lift and shift, move it as-is. It's the fastest of the six
standard strategies (replatform, refactor, repurchase, retain, retire being the
others), and it's usually the right starting point when the goal is "get off this
platform" rather than "redesign the app while we're at it."

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

## What's actually in this repo

- Terraform for both sides - the Azure source VM and the AWS VPC/subnets/security
  groups MGN needs
- A real runbook for replication, testing, validation, and cutover
- A script to check network reachability before you even start the agent install,
  because half the MGN issues I've run into trace back to a blocked port, not MGN
  itself
- A validation script that diffs source vs. target content before you commit to
  cutover
- A rollback plan that isn't just "destroy everything and hope"

## Tech stack

Terraform, Azure (VM, VNet), AWS (VPC, EC2, MGN), AWS Application Migration
Service, and a couple of small Python scripts for the validation/readiness checks.

---

## Prerequisites

- Terraform >= 1.5.0
- Azure CLI logged in (`az login`)
- AWS CLI configured (`aws configure`)
- An SSH key pair for the Azure VM (`ssh-keygen` if you don't already have one)

---

## Part 1 - Provision the source and target infra

```bash
git clone https://github.com/JSR-codes/azure-to-aws-vm-migration.git
cd azure-to-aws-vm-migration

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars - azure_subscription_id and my_ip are required

terraform init
terraform plan
terraform apply
```

This stands up the Azure source VM (running nginx, standing in for a real
workload) and the AWS side - VPC, subnets, security groups - that MGN needs to
land replicated data.

## Part 1.5 - Check network readiness before you touch the agent

Don't skip this. Before installing the replication agent, make sure the source VM
can actually reach what MGN needs on the AWS side - port 443 for the API, port
1500 for replication traffic. If an NSG rule or a route is wrong, the agent
install will look totally fine and replication will just sit at 0% with no
obvious reason why. I've lost time to this exact thing before, hence the script.

```bash
ssh azureuser@<azure_source_vm_public_ip>
python3 scripts/check_network_readiness.py <aws_endpoint_or_ip>
```

If anything comes back FAIL, fix it before moving to Part 3.

## Part 2 - Initialize AWS MGN (one-time per account/region)

```bash
aws mgn initialize-service --region us-east-1
```

## Part 3 - Install the replication agent on the source VM

SSH into the Azure VM (use the `azure_source_vm_public_ip` output), then grab the
current install command from the MGN console - **Source servers → Add source
server** - or the [official docs](https://docs.aws.amazon.com/mgn/latest/ug/installing-the-agent.html).
It looks roughly like this:

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

Once it connects, the source server shows up in the MGN console and continuous
replication into the staging subnet starts on its own.

## Part 4 - Launch a test instance

Once replication hits 100% in the console, pick the source server and choose
**Launch test instance**. This spins up a copy in your AWS target subnet without
touching the still-running Azure source - it's your safety net before you
commit to anything.

## Part 5 - Validate before you cut over

```bash
python3 scripts/validate_migration.py <azure_source_ip> <test_instance_ip>
```

This just hashes and compares what each side actually serves. If you get a
MISMATCH, stop and figure out why before going anywhere near cutover.

## Part 6 - Cutover

Back in the MGN console: source server → **Launch cutover instance**. This is the
point of no return for the exercise - equivalent to pointing real production
traffic at the new instance. In an actual migration this is where DNS, load
balancer targets, or connection strings would get repointed.

## Part 7 - Decommission the source

Only after you've confirmed the cutover instance has been healthy for a
reasonable soak period:

```bash
terraform destroy -target=azurerm_linux_virtual_machine.source
```

Or just tear the whole thing down once you're done - see Cleanup below.

---

## Rollback plan

If something looks off after cutover:
- The Azure VM is left alone until you explicitly destroy it, so it's still there
  as a fallback
- Point traffic back at the Azure source's IP/DNS
- Check the MGN replication logs, fix whatever broke, and try cutover again

This is the whole reason for doing a test instance before the real cutover - it's
a real checkpoint, not just a box to tick.

---

## Cleanup

```bash
terraform destroy
```

Worth also checking the MGN console directly - the source server and its
replication/staging resources on the AWS side are managed by MGN itself, not this
Terraform config, so they need to be disconnected/terminated there too or you'll
keep getting billed.

## Cost notes

MGN is free for the first 90 days per source server, then it's billed hourly -
fine for a demo like this, just don't leave it "replicating" forever. The Azure
VM and whatever AWS instances are running bill normally the whole time too.

## Things I'd add if I kept going

- Automate the agent install with Terraform `remote-exec`, using scoped-down
  temporary IAM creds instead of doing it by hand
- Add a second source server and try migrating a small multi-tier app instead of
  a single VM
- Actually practice a failback (AWS back to Azure) instead of just writing that
  it's possible

## License

MIT
