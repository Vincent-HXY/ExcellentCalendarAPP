"""Executable v6 DDL/migration oracle, never a product storage implementation.

The migration input is checked by the unchanged C++ v5 runtime. The isolated
oracle uses Python SQLite for logical-schema checks; account encryption is a
separate SQLCipher experiment and cannot be certified by this module.
"""
from __future__ import annotations

import atexit
import functools
import json
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import tempfile
import time

from build_sync_storage_contract import derive, CONTRACTS
from sqlite_reference import connect

WORKSPACE = "99999999-9999-4999-8999-999999999999"
NOW = "2026-09-05T00:00:00Z"


@functools.lru_cache(maxsize=1)
def build_probe():
    scratch = Path(tempfile.mkdtemp(prefix="excellent-calendar-v6-checker-")).resolve()
    assert scratch.parent == Path(tempfile.gettempdir()).resolve() and scratch.name.startswith("excellent-calendar-v6-checker-")

    def cleanup():
        # Windows may briefly retain the just-executed image. Avoid Python 3.10
        # TemporaryDirectory's file-as-directory fallback and retry that lock.
        for attempt in range(6):
            try:
                shutil.rmtree(scratch)
                return
            except FileNotFoundError:
                return
            except PermissionError:
                if attempt == 5:
                    raise
                time.sleep(0.2 * (attempt + 1))

    atexit.register(cleanup)
    root = CONTRACTS.parent
    probe = scratch / "storage_v5_probe.exe"
    command = ["D:/mingw/mingw64/bin/g++.exe", "-std=c++17", "-O2", "-finput-charset=UTF-8",
        "-I", str(root / "cpp_core/include"), "-I", str(root / "cpp_core/third_party"),
        str(CONTRACTS / "spikes/sync_v1/storage_v5_probe.cpp")]
    command += [str(root / "cpp_core/build-ninja" / name) for name in (
        "libexcellent_calendar_core.a", "libexcellent_calendar_date_tz.a", "libexcellent_calendar_sqlite.a")]
    command += ["-lbcrypt", "-pthread", "-o", str(probe)]
    subprocess.run(command, check=True, capture_output=True)
    return probe


def frozen_check(probe, directory):
    result = subprocess.run([str(probe), "check", str(directory)], capture_output=True, text=True, encoding="utf-8")
    if result.returncode or result.stdout.strip() != "V5_VALID":
        raise ValueError("FROZEN_V5_CHECKER_REJECTED: " + result.stdout.strip())


def normalized(sql):
    return re.sub(r"[\s;]", "", sql).lower()


def snapshot(path):
    with connect(path) as db:
        result = {}
        for (name,) in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"):
            result[name] = sorted(db.execute('SELECT * FROM "' + name + '"').fetchall(), key=repr)
        result["objects"] = list(db.execute("SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name"))
        result["user_version"] = db.execute("PRAGMA user_version").fetchone()[0]
        return result


def validate_new_codecs(db, definition):
    from domain_reference import validate_fact, definitions
    from protocol_reference import digest, mutation_hash
    from validate_sync_v1 import read_json, read_yaml, unique_object, invalid_constant, Draft202012Validator, FormatChecker
    registry, fields = definitions()
    errors = read_yaml(CONTRACTS / "sync/sync_error_registry.yaml")["errors"]
    preferences = db.execute("SELECT timezone,habit_progress_color,default_reminder_methods_json,auto_enable_reminders_on_other_devices FROM workspace_preferences WHERE singleton=1").fetchone()
    if preferences is None:
        raise ValueError("V6_PREFERENCES_MISSING")
    try:
        validate_fact({"target_type": "user_preferences", "target_id": WORKSPACE,
            "fact": {"timezone": preferences[0], "habit_progress_color": preferences[1],
                "default_reminder_methods": json.loads(preferences[2]), "auto_enable_reminders_on_other_devices": bool(preferences[3])}})
        for table, codec in definition["payload_codecs"].items():
            names = [column[1] for column in db.execute('PRAGMA table_info("' + table + '")')]
            for values in db.execute('SELECT * FROM "' + table + '"'):
                row = dict(zip(names, values))
                decoded = {}
                for column, schema_path in codec.get("columns", {}).items():
                    value = row[column]
                    if value is None and schema_path != "sync/sync_error_registry.yaml":
                        continue
                    value = json.loads(value, object_pairs_hook=unique_object, parse_constant=invalid_constant) if value is not None else None
                    decoded[column] = value
                    if ".schema.json" in schema_path:
                        relative, _, pointer = schema_path.partition("#")
                        schema = read_json(CONTRACTS / relative)
                        for key in pointer.lstrip("/").split("/") if pointer else []:
                            schema = schema[int(key)] if isinstance(schema, list) else schema[key]
                        if not Draft202012Validator(schema, registry=registry, format_checker=FormatChecker()).is_valid(value):
                            raise ValueError("V6_PAYLOAD_CODEC_INVALID")
                    elif schema_path == "nonempty_sorted_unique_uuid_array":
                        import uuid
                        if not value or value != sorted(set(value)) or any(str(uuid.UUID(v)) != v for v in value):
                            raise ValueError("V6_NOTICE_IDENTITY_INVALID")
                    elif schema_path in {"target_registry_merge_key_safe_integer_map", "target_registry_unique_merge_keys"}:
                        allowed = set().union(*(v["merge_groups"] for v in fields["targets"][row["target_type"]]["variants"].values()))
                        if not set(value) <= allowed:
                            raise ValueError("V6_FIELD_KEY_INVALID")
                        if schema_path.endswith("safe_integer_map"):
                            from counter_reference import integer
                            for version in value.values():
                                integer(version)
                        elif not isinstance(value, list) or len(value) != len(set(value)):
                            raise ValueError("V6_FIELD_KEY_INVALID")
                    elif schema_path in {"target_specific_fact", "target_specific_patch"}:
                        target = row["target_type"]
                        variant = value.get("owner_type", "default") if target == "reminder_intent" else "default"
                        definition_row = fields["targets"][target]["variants"][variant]
                        path = definition_row["fact_schema" if schema_path.endswith("fact") else "patch_schema"]
                        if path is None or not Draft202012Validator(read_json(CONTRACTS / path), registry=registry, format_checker=FormatChecker()).is_valid(value):
                            raise ValueError("V6_PAYLOAD_CODEC_INVALID")
                    elif schema_path == "sync/sync_error_registry.yaml":
                        if not Draft202012Validator(errors[row["failure_code"]]["context_schema"], registry=registry, format_checker=FormatChecker()).is_valid(value):
                            raise ValueError("V6_FAILURE_CONTEXT_INVALID")
                    else:
                        raise ValueError("V6_UNKNOWN_PAYLOAD_CODEC")
                if "payload_json" in decoded:
                    if row["payload_version"] != 1:
                        raise ValueError("V6_PAYLOAD_VERSION_INVALID")
                    hashed = mutation_hash(decoded["payload_json"]) if table == "sync_outbox" else digest(decoded["payload_json"])
                    if row["payload_hash"] != hashed:
                        raise ValueError("V6_PAYLOAD_HASH_INVALID")
                    if table == "sync_outbox":
                        mutation = decoded["payload_json"]
                        for key in ("mutation_id", "client_sequence", "target_type", "target_id", "operation_type", "base_entity_version", "created_at"):
                            if mutation[key] != row[key]:
                                raise ValueError("V6_OUTBOX_INDEX_INVALID")
                        if mutation["causal_predecessors"] != decoded["causal_predecessors_json"]:
                            raise ValueError("V6_OUTBOX_INDEX_INVALID")
                    if table == "guest_import_source_lease_replacements":
                        previous = decoded["payload_json"]
                        current = db.execute("SELECT reserved_operation_id,source_epoch,lineage_id,protected_owner_binding_digest,state,lease_revision "
                            "FROM guest_import_source_leases WHERE source_workspace_id=?", (row["source_workspace_id"],)).fetchone()
                        if (current is None or current[:4] != (row["operation_id"], row["source_epoch"], previous["lineage_id"], previous["protected_owner_binding_digest"])
                            or current[4] != "reserved" or current[5] <= previous["lease_revision"]
                            or row["source_workspace_id"] != previous["source_workspace_id"] or row["source_epoch"] != previous["source_epoch"]
                            or previous["terminal_client_sequence"] <= previous["begin_client_sequence"]):
                            raise ValueError("V6_IMPORT_LEASE_BACKUP_INVALID")
    except (AssertionError, KeyError, TypeError, json.JSONDecodeError) as error:
        raise ValueError("V6_PAYLOAD_CODEC_INVALID") from error


def migrate(probe, directory, *, kind="local", fail_at=None):
    if kind != "local":
        raise ValueError("SQLCIPHER_BINDING_REQUIRED")
    definition = derive()
    path = Path(directory) / "calendar_core.sqlite3"
    frozen_check(probe, directory)
    with connect(path) as db:
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("BEGIN IMMEDIATE")
        if db.execute("PRAGMA user_version").fetchone()[0] != 5:
            raise ValueError("STORAGE_VERSION_CHANGED")
        for n, statement in enumerate([*definition["new_tables"].values(), *definition["new_indexes"].values(), *definition["new_triggers"].values()]):
            db.execute(statement)
            if fail_at == n:
                raise RuntimeError("INJECTED_DDL_ROLLBACK")
        db.execute("INSERT INTO workspace_metadata VALUES(1,?,?,?,?,?,?,?,?,?,?)", (WORKSPACE, kind,
            None, 6, "guest_plaintext_v1", NOW, 0, None, 0, 0))
        db.execute("INSERT INTO workspace_preferences VALUES(1,?,?,?,?,?)", ("Asia/Shanghai", "teal", '["popup"]', 0, 0))
        for key, value in definition["migration"]["metadata_updates"].items():
            assert db.execute("UPDATE schema_metadata SET value=? WHERE key=?", (value, key)).rowcount == 1
        for key, value in definition["migration"]["metadata_additions"].items():
            db.execute("INSERT INTO schema_metadata VALUES(?,?)", (key, value))
        h = definition["migration"]["history"]
        db.execute("INSERT INTO migration_history VALUES(?,?,?,?,?)", (h["migration_id"], h["source_format"], 5, 6, NOW))
        if fail_at == "history":
            raise RuntimeError("INJECTED_HISTORY_ROLLBACK")
        db.execute("PRAGMA user_version=6")
        if fail_at == "before_commit":
            raise RuntimeError("INJECTED_COMMIT_ROLLBACK")
        assert db.execute("PRAGMA quick_check").fetchone() == ("ok",)
    return path


def validate(probe, directory, inherited_objects, inherited_metadata, *, profile="guest_plaintext_v1"):
    definition = derive()
    path = Path(directory) / "calendar_core.sqlite3"
    with connect(path) as db:
        if db.execute("PRAGMA user_version").fetchone() != (6,):
            raise ValueError("V6_VERSION_INVALID")
        if db.execute("PRAGMA application_id").fetchone() != (0x4543414c,):
            raise ValueError("V6_APPLICATION_ID_INVALID")
        if db.execute("PRAGMA quick_check").fetchone() != ("ok",) or list(db.execute("PRAGMA foreign_key_check")):
            raise ValueError("V6_CORRUPT")
        actual = {name: (kind, normalized(sql)) for kind, name, sql in db.execute("SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL")}
        expected = {name: (kind, normalized(sql)) for kind, name, sql in inherited_objects}
        for label, kind in (("new_tables", "table"), ("new_indexes", "index"), ("new_triggers", "trigger")):
            expected.update({name: (kind, normalized(sql)) for name, sql in definition[label].items()})
        if actual != expected:
            raise ValueError("V6_DDL_INVALID")
        metadata = dict(inherited_metadata)
        metadata.update(definition["migration"]["metadata_updates"])
        metadata.update(definition["migration"]["metadata_additions"])
        if dict(db.execute("SELECT key,value FROM schema_metadata")) != metadata:
            raise ValueError("V6_METADATA_INVALID")
        if db.execute("SELECT encryption_profile FROM workspace_metadata WHERE singleton=1").fetchone() != (profile,):
            raise ValueError("V6_PROFILE_INVALID")
        history = db.execute("SELECT source_format,source_version,target_version,completed_at FROM migration_history WHERE migration_id=?", (definition["migration"]["history"]["migration_id"],)).fetchone()
        if history is None or history[:3] != ("excellent_calendar_core_sqlite", 5, 6) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", history[3]):
            raise ValueError("V6_HISTORY_INVALID")
        validate_new_codecs(db, definition)
        # v5 checker is used on an isolated projection to verify ALL inherited
        # codecs/relations/metadata/history. This projection is test-only; product
        # v6 must reuse frozen checker routines in-place without copying a DB.
        with tempfile.TemporaryDirectory(prefix="excellent-calendar-v5-projection-") as scratch:
            clone = Path(scratch) / "calendar_core.sqlite3"
            with connect(clone) as projected:
                db.backup(projected)
            with connect(clone) as projected:
                projected.execute("PRAGMA foreign_keys=OFF")
                for name in definition["new_tables"]:
                    projected.execute('DROP TABLE "' + name + '"')
                for key in definition["migration"]["metadata_additions"]:
                    projected.execute("DELETE FROM schema_metadata WHERE key=?", (key,))
                for key in definition["migration"]["metadata_updates"]:
                    projected.execute("UPDATE schema_metadata SET value=? WHERE key=?", (dict(inherited_metadata)[key], key))
                projected.execute("DELETE FROM migration_history WHERE migration_id=?", (definition["migration"]["history"]["migration_id"],))
                projected.execute("PRAGMA user_version=5")
            frozen_check(probe, scratch)
    return True
