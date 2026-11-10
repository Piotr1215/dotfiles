#!/usr/bin/env python3
"""Sync temporary sandbox profiles with the default AWS SSO session."""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path


def aws_sso(operation, token, **parameters):
    """Pass the token to AWS CLI through an anonymous file, not argv."""
    fd = os.memfd_create("aws-sso-input")
    try:
        os.write(fd, json.dumps({"accessToken": token, **parameters}).encode())
        os.lseek(fd, 0, os.SEEK_SET)
        result = subprocess.run(
            ["aws", "sso", operation, "--region", "eu-central-1", "--output", "json",
             "--no-cli-pager", "--cli-input-json", f"file:///proc/self/fd/{fd}"],
            pass_fds=(fd,), capture_output=True, text=True, check=True,
        )
        return json.loads(result.stdout)
    finally:
        os.close(fd)


def main():
    config = Path(os.environ.get("AWS_CONFIG_FILE", Path.home() / ".aws/config"))
    cache = Path.home() / ".aws/sso/cache" / (hashlib.sha1(b"default").hexdigest() + ".json")
    original = config.read_bytes()
    token = json.loads(cache.read_text())["accessToken"]
    accounts = aws_sso("list-accounts", token)["accountList"]
    sandbox_ids = []
    for account in accounts:
        account_id = account["accountId"]
        if not re.fullmatch(r"\d{12}", account_id):
            raise ValueError("invalid account ID returned by AWS")
        roles = aws_sso("list-account-roles", token, accountId=account_id)["roleList"]
        if any(role["roleName"] == "Sandbox-Admin-12h" for role in roles):
            sandbox_ids.append(account_id)

    text = original.decode()
    sections = re.split(r"(?=^\[[^\]\n]+\][^\n]*(?:\n|$))", text, flags=re.MULTILINE)
    kept = [s for s in sections if not re.match(r"\[profile sandbox-\d{12}\]\s*(?:\n|$)", s)]
    updated = "".join(kept)
    if updated and not updated.endswith("\n"):
        updated += "\n"
    for account_id in sorted(set(sandbox_ids)):
        updated += (f"[profile sandbox-{account_id}]\nsso_session = default\n"
                    f"sso_account_id = {account_id}\nsso_role_name = Sandbox-Admin-12h\n"
                    "region = eu-central-1\n")
    if updated.encode() == original:
        print("Sandbox profiles already match AWS SSO.")
        return
    if config.read_bytes() != original:
        raise RuntimeError("AWS config changed during sync; retry")
    backup = config.with_name(config.name + ".bak-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
    shutil.copy2(config, backup)
    fd, temp = tempfile.mkstemp(prefix=".aws-config-", dir=config.parent)
    try:
        os.fchmod(fd, config.stat().st_mode & 0o777)
        with os.fdopen(fd, "w") as output:
            output.write(updated)
        if config.read_bytes() != original:
            raise RuntimeError("AWS config changed during sync; retry")
        os.replace(temp, config)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    print(f"Backup: {backup}")
    print("Sandbox accounts: " + (", ".join(sorted(set(sandbox_ids))) or "none"))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, RuntimeError) as exc:
        print(f"Sandbox profile sync failed: {exc}", file=sys.stderr)
        sys.exit(1)
