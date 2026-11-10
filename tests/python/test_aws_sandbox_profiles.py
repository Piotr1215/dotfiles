import hashlib
import importlib.util
import json
from pathlib import Path
from unittest.mock import patch

import pytest


spec = importlib.util.spec_from_file_location(
    "sandbox_profiles", Path(__file__).parents[2] / "scripts/__aws_sandbox_profiles.py"
)
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


@pytest.fixture
def setup_config(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    config = tmp_path / ".aws/config"
    config.parent.mkdir()
    config.write_text("[profile prod]\nsso_account_id = 123\n"
                      "[profile sandbox-888782968602]\nsso_session = default\n"
                      "[profile management]\nregion = eu-central-1\n")
    cache = tmp_path / ".aws/sso/cache"
    cache.mkdir(parents=True)
    (cache / (hashlib.sha1(b"default").hexdigest() + ".json")).write_text(
        json.dumps({"accessToken": "test-token"})
    )
    return config


def test_reconciles_sandbox_and_preserves_other_profiles(setup_config):
    def fake(operation, token, **kwargs):
        if operation == "list-accounts":
            return {"accountList": [{"accountId": "111111111111"}, {"accountId": "222222222222"}]}
        role = "Sandbox-Admin-12h" if kwargs["accountId"] == "111111111111" else "Administrator"
        return {"roleList": [{"roleName": role}]}

    original = setup_config.read_text()
    with patch.object(sync, "aws_sso", fake):
        sync.main()
        updated = setup_config.read_text()
        sync.main()
    assert "sandbox-888782968602" not in updated
    assert "sandbox-111111111111" in updated
    assert "sandbox-222222222222" not in updated
    assert "[profile prod]\nsso_account_id = 123\n" in updated
    assert "[profile management]\nregion = eu-central-1\n" in updated
    backups = list(setup_config.parent.glob("config.bak-*"))
    assert len(backups) == 1 and backups[0].read_text() == original


def test_failed_inventory_does_not_modify_config(setup_config):
    original = setup_config.read_bytes()
    with patch.object(sync, "aws_sso", side_effect=RuntimeError("offline")), pytest.raises(RuntimeError):
        sync.main()
    assert setup_config.read_bytes() == original
    assert not list(setup_config.parent.glob("config.bak-*"))
