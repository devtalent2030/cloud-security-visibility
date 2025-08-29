#!/usr/bin/env python3
"""
Onboard all existing AWS Organization accounts into Security Hub
under the delegated admin (Auth) account.

Usage:
  python create_members.py <delegated_admin_account_id> <cross_account_role_name> [region]

Example:
  python create_members.py 030172395295 CrossAccount-SecurityOps us-east-1
"""

import sys
import time
from typing import List, Dict, Set

import boto3
from botocore.exceptions import ClientError

DEFAULT_REGION = "us-east-1"


def assume_role(account_id: str, role_name: str, session_name: str, region: str):
    sts = boto3.client("sts", region_name=region)
    resp = sts.assume_role(
        RoleArn=f"arn:aws:iam::{account_id}:role/{role_name}",
        RoleSessionName=session_name,
    )
    creds = resp["Credentials"]
    return boto3.Session(
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
        region_name=region,
    )


def list_all_org_accounts(org_client) -> List[Dict]:
    accounts: List[Dict] = []
    paginator = org_client.get_paginator("list_accounts")
    for page in paginator.paginate(PaginationConfig={"PageSize": 20}):
        accounts.extend(page.get("Accounts", []))
    # Only ACTIVE accounts are relevant
    return [a for a in accounts if a.get("Status") == "ACTIVE"]


def get_existing_member_ids(sh_client) -> Set[str]:
    """Return set of account IDs already known to Security Hub (associated or not)."""
    existing: Set[str] = set()
    paginator = sh_client.get_paginator("list_members")
    # OnlyAssociated=False includes invited/unassociated too
    for page in paginator.paginate(OnlyAssociated=False):
        for m in page.get("Members", []):
            if "AccountId" in m:
                existing.add(m["AccountId"])
    return existing


def chunk(iterable, size):
    """Yield lists of length <= size."""
    batch = []
    for item in iterable:
        batch.append(item)
        if len(batch) == size:
            yield batch
            batch = []
    if batch:
        yield batch


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    delegated_admin_acct = sys.argv[1].strip()
    cross_account_role = sys.argv[2].strip()
    region = sys.argv[3].strip() if len(sys.argv) > 3 else DEFAULT_REGION

    # 1) Use current credentials (Management account) to list all org accounts
    org = boto3.client("organizations", region_name=region)
    sts = boto3.client("sts", region_name=region)
    caller = sts.get_caller_identity()
    mgmt_account_id = caller.get("Account")
    print(f"[INFO] Using Management account credentials: {mgmt_account_id}")

    accounts = list_all_org_accounts(org)
    print(f"[INFO] Discovered {len(accounts)} ACTIVE org accounts.")

    # 2) Assume into the delegated admin (Auth) to talk to Security Hub
    print(f"[INFO] Assuming role into delegated admin {delegated_admin_acct}:{cross_account_role}")
    delegated_sess = assume_role(
        account_id=delegated_admin_acct,
        role_name=cross_account_role,
        session_name="SecurityHubDelegatedAdmin",
        region=region,
    )
    sh = delegated_sess.client("securityhub")

    # Sanity: ensure Security Hub is enabled in delegated admin
    try:
        _ = sh.get_master_account()
    except ClientError as e:
        # get_master_account is deprecated in favor of get_administrator_account in some regions;
        # we just ensure the API is reachable. If disabled, this will error out differently.
        try:
            _ = sh.get_administrator_account()
        except ClientError as e2:
            print("[ERROR] Security Hub may not be enabled in the delegated admin account.")
            print(f"        Underlying error: {e2}")
            sys.exit(2)

    # 3) Determine which accounts need to be created as members
    existing_member_ids = get_existing_member_ids(sh)
    print(f"[INFO] Security Hub already knows about {len(existing_member_ids)} accounts.")

    to_create: List[Dict] = []
    for a in accounts:
        aid = a["Id"]
        email = a["Email"]
        name = a.get("Name", "")
        # Skip the delegated admin itself
        if aid == delegated_admin_acct:
            continue
        # Skip accounts already present
        if aid in existing_member_ids:
            continue
        to_create.append({"AccountId": aid, "Email": email})

    print(f"[INFO] Accounts to create as members: {len(to_create)}")

    created = 0
    unprocessed = []
    # Security Hub create_members accepts up to 50 accounts per call
    for batch in chunk(to_create, 50):
        try:
            resp = sh.create_members(AccountDetails=batch)
            unp = resp.get("UnprocessedAccounts", [])
            if unp:
                unprocessed.extend(unp)
            created += len(batch) - len(unp)
            # Avoid throttling on very large orgs
            time.sleep(0.25)
        except ClientError as e:
            print(f"[ERROR] create_members failed for batch: {e}")
            unprocessed.extend([{"AccountId": x["AccountId"], "ProcessingResult": str(e)} for x in batch])

    # 4) Optional: invite members (some org setups require invite/accept)
    # If you want to send invitations, uncomment below lines:
    # try:
    #     for batch in chunk([a["AccountId"] for a in to_create], 50):
    #         sh.invite_members(AccountIds=batch)
    #         time.sleep(0.25)
    #     print("[INFO] Invitations sent to newly created members.")
    # except ClientError as e:
    #     print(f"[WARN] invite_members failed: {e}")

    # 5) Final summary
    print("----- SUMMARY -----")
    print(f"Delegated admin account: {delegated_admin_acct}")
    print(f"Management account:      {mgmt_account_id}")
    print(f"Region:                  {region}")
    print(f"Existing known members:  {len(existing_member_ids)}")
    print(f"Requested create:        {len(to_create)}")
    print(f"Successfully created:    {created}")
    if unprocessed:
        print(f"Unprocessed ({len(unprocessed)}):")
        for u in unprocessed[:10]:
            print(f"  - {u.get('AccountId')} :: {u.get('ProcessingResult')}")
        if len(unprocessed) > 10:
            print("  ... (truncated)")

    print("[INFO] Done.")
    print("Note: New accounts created after today will auto-enroll via your org configuration (auto_enable = true).")


if __name__ == "__main__":
    main()
