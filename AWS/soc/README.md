# Cloud Native Security Operations Center (SOC) on AWS

##  Overview
This project implements **Recipe 3.2: Building a Cloud Native Security Operations Center on AWS**, aligning with modern enterprise security practices.  
It establishes a **centralized Security Hub** that aggregates security findings across an AWS Organization and enforces **consistent security posture management**.

The deployment leverages **Terraform (infrastructure as code)** and **Python automation** to bootstrap, delegate, and operationalize Security Hub at scale.

---

##  Problem
Enterprises operating multiple AWS accounts face:
- Fragmented visibility into security posture.
- Duplication of manual effort enabling Security Hub per account.
- Inconsistent standards adoption (CIS, AWS Best Practices).
- Delayed detection and triage of security issues.

---

## ✅ Solution
This SOC design centralizes Security Hub administration into a **dedicated delegated admin account ("Auth")**, ensuring:
- **Single pane of glass** for security posture across all accounts.
- **Automatic enrollment** of new AWS Organization accounts.
- **Industry-standard benchmarks** (CIS v1.4, AWS Foundational Security Best Practices).
- **Scalable onboarding** of existing accounts via automation.

The workflow is broken into **Terraform (infra setup)** + **Python (member onboarding)**:

---

### 1. Organization Setup with Terraform
- Enable **Security Hub** at the **Organization level**.
- Elect a **delegated administrator account** (`Auth` account).
- Configure **auto-enrollment** for future AWS accounts.

Key Terraform resources:
- `aws_organizations_organization.this`  
- `aws_securityhub_organization_admin_account.delegate`  
- `aws_securityhub_account.enable_in_admin`  
- `aws_securityhub_standards_subscription.standards`  
- `aws_securityhub_organization_configuration.org_auto`  

> **Outcome:** Any new account joining the Organization is automatically enrolled into Security Hub.

---

### 2. Standards Subscriptions
Using Terraform:
- **CIS AWS Foundations Benchmark v1.4.0**  
- **AWS Foundational Security Best Practices v1.0.0**

> **Outcome:** Automated posture checks aligned with security/compliance frameworks.

---

### 3. Onboarding Existing Accounts with Python
Terraform only handles **new accounts** automatically.  
To bootstrap **existing accounts**, we used a Python script:

```bash
python create_members.py <delegated_admin_account_id> <cross_account_role> us-east-1
````

* Enumerates all **active AWS Organization accounts**.
* Uses `sts:AssumeRole` into delegated admin.
* Calls `securityhub.create_members` to register accounts into Security Hub.

> **Outcome:** All 6 existing Organization accounts were successfully added as Security Hub members.

---

##  Validation

Commands used to validate configuration:

```bash
aws organizations list-delegated-administrators \
  --service-principal securityhub.amazonaws.com

aws securityhub describe-organization-configuration --region us-east-1

aws securityhub list-members --no-only-associated --region us-east-1 \
  --query 'Members[].{AccountId:AccountId,Status:MemberStatus}' --output table
```

* **Delegated admin** confirmed (`Auth` account).
* **Auto-enable = true** verified.
* **All member accounts** listed as `Enabled`.

---

##  Security Hub Findings

Once enabled, Security Hub begins aggregating findings from:

* **Amazon GuardDuty**
* **Amazon Inspector**
* **AWS Config**
* **IAM Access Analyzer**
* **Amazon Macie**
* **Third-party integrations**

Additionally, we injected a **custom portfolio demo finding** via `batch-import-findings` to verify ingestion pipelines.

---

##  Key Takeaways

* **Security Hub as SOC:** Provides a centralized, auditable, and scalable way to monitor AWS security posture.
* **Delegated Admin Pattern:** Separates security operations from workload accounts, improving governance.
* **IaC + Automation:** Terraform for structure, Python for member onboarding = reproducible and scalable SOC setup.
* **Cost Control:** SOC skeleton created with **no billable scanning engines enabled** (Inspector, GuardDuty, Macie). Safe for portfolio/demo use.

---

##  Tech Stack

* **Terraform** (AWS provider v3.x)
* **Python 3 + boto3**
* **AWS Security Hub**
* **AWS Organizations + IAM Cross-Account Roles**

---

##  Repo Structure (example)

```
AWS/soc/
├── main.tf                # Terraform Security Hub + Org config
├── provider.tf            # Root + Delegated admin providers
├── variables.tf           # Input variables (delegated admin, cross-account role, region)
├── terraform.tfvars       # Values for variables
├── create_members.py      # Python automation to onboard existing accounts
├── requirements.txt       # Python dependencies (boto3)
└── README.md              # This file
```

---

## Future Enhancements

* Enable **GuardDuty, Inspector, Macie** org-wide for real threat + PII coverage.
* Integrate **Security Hub → SIEM** (Splunk, Elastic, or AWS OpenSearch).
* Extend **automated remediations** using Security Hub + Systems Manager Automation runbooks.

---

## Demo Context

This SOC implementation is for **portfolio/demo purposes**.
It creates **no recurring cost** unless GuardDuty/Inspector/Macie are explicitly enabled at scale.
