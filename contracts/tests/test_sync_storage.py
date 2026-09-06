"""Physical SQLite checks, including unchanged native v5 validation and downgrade."""
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts"),
                str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_sync_storage_contract import derive, yaml
from storage_reference import build_probe, frozen_check, migrate, snapshot, validate
from sqlite_reference import connect


class StorageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.probe = build_probe()

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="excellent-calendar-v6-test-")
        self.addCleanup(self.scratch.cleanup)
        self.directory = Path(self.scratch.name)
        self.path = self.directory / "calendar_core.sqlite3"
        subprocess.run([str(self.probe), "create", str(self.directory)], check=True, capture_output=True)
        self.before = snapshot(self.path)
        self.assertEqual(self.before["user_version"], 5)
        self.assertEqual(len(self.before["habits"]), 1)

    def validate(self, **options):
        return validate(self.probe, self.directory, self.before["objects"], self.before["schema_metadata"], **options)

    def test_exact_machine_definition_and_complete_legacy_projection(self):
        document = yaml.safe_load((ROOT / "contracts/storage/calendar_core_storage.yaml").read_text(encoding="utf-8"))
        self.assertEqual(document["calendar_core_v6"], derive())
        self.assertEqual(len(self.before["objects"]), 44)
        migrate(self.probe, self.directory)
        self.assertTrue(self.validate())
        after = snapshot(self.path)
        for name, rows in self.before.items():
            if name not in {"objects", "user_version", "schema_metadata", "migration_history"}:
                self.assertEqual(after[name], rows, name)
        self.assertEqual(len(after["migration_history"]), len(self.before["migration_history"]) + 1)
        self.assertEqual([r for r in after["migration_history"] if r in self.before["migration_history"]], self.before["migration_history"])

    def test_every_added_ddl_boundary_and_history_rollback_is_atomic(self):
        backup = self.directory / "source.sqlite3"
        shutil.copy2(self.path, backup)
        d = derive()
        boundaries = [*range(len(d["new_tables"]) + len(d["new_indexes"]) + len(d["new_triggers"])), "history", "before_commit"]
        for at in boundaries:
            with self.subTest(at=at), self.assertRaisesRegex(RuntimeError, "INJECTED"):
                migrate(self.probe, self.directory, fail_at=at)
            self.assertEqual(snapshot(self.path), self.before)
            frozen_check(self.probe, self.directory)
        backup.unlink()

    def test_old_runtime_rejects_v6_and_cannot_rewrite_it(self):
        migrate(self.probe, self.directory)
        before = snapshot(self.path)
        with self.assertRaisesRegex(ValueError, "FROZEN_V5_CHECKER_REJECTED"):
            frozen_check(self.probe, self.directory)
        self.assertEqual(snapshot(self.path), before)
        with self.assertRaisesRegex(ValueError, "FROZEN_V5_CHECKER_REJECTED"):
            migrate(self.probe, self.directory)
        self.assertEqual(snapshot(self.path), before)

    def test_corrupt_v5_codec_rejects_before_any_v6_object_or_metadata(self):
        with connect(self.path) as db:
            db.execute("UPDATE habits SET payload_json=json_set(payload_json,'$.target_count_hundredths',9007199254740992)")
        corrupted = snapshot(self.path)
        with self.assertRaisesRegex(ValueError, "FROZEN_V5_CHECKER_REJECTED"):
            migrate(self.probe, self.directory)
        self.assertEqual(snapshot(self.path), corrupted)

    def test_corrupt_v6_definition_and_unknown_metadata_fail_closed(self):
        migrate(self.probe, self.directory)
        with connect(self.path) as db:
            db.execute("DROP INDEX ix_sync_outbox_state_sequence")
            db.execute("CREATE INDEX ix_sync_outbox_state_sequence ON sync_outbox(target_id)")
        with self.assertRaisesRegex(ValueError, "V6_DDL_INVALID"):
            self.validate()
        with connect(self.path) as db:
            db.execute("DROP INDEX ix_sync_outbox_state_sequence")
            db.execute(derive()["new_indexes"]["ix_sync_outbox_state_sequence"])
            db.execute("INSERT INTO schema_metadata VALUES('unknown','1')")
        with self.assertRaisesRegex(ValueError, "V6_METADATA_INVALID"):
            self.validate()

    def test_v6_checks_inherited_relations_and_illegal_history(self):
        migrate(self.probe, self.directory)
        with connect(self.path) as db:
            db.execute("UPDATE habits SET payload_json=json_set(payload_json,'$.recurrence_id','22222222-2222-4222-8222-222222222222')")
        with self.assertRaisesRegex(ValueError, "FROZEN_V5_CHECKER_REJECTED"):
            self.validate()

    def test_guest_rejects_account_tables_and_wrong_encryption_profile(self):
        with self.assertRaisesRegex(ValueError, "SQLCIPHER_BINDING_REQUIRED"):
            migrate(self.probe, self.directory, kind="account")
        self.assertEqual(snapshot(self.path), self.before)
        migrate(self.probe, self.directory)
        with connect(self.path) as db:
            with self.assertRaisesRegex(sqlite3.IntegrityError, "WORKSPACE_ACCOUNT_MISMATCH"):
                db.execute("INSERT INTO sync_change_receipts VALUES(0,1,?,'2026-09-05T00:00:00Z')", ("a" * 64,))
            self.assertEqual(db.execute("SELECT count(*) FROM sync_outbox").fetchone()[0], 0)
            with self.assertRaises(sqlite3.IntegrityError):
                db.execute("UPDATE workspace_metadata SET encryption_profile='account_sqlcipher_v1'")
        with self.assertRaisesRegex(ValueError, "V6_PROFILE_INVALID"):
            self.validate(profile="account_sqlcipher_v1")

    def test_safe_integer_and_source_epoch_gate_constraints(self):
        migrate(self.probe, self.directory)
        with connect(self.path) as db:
            for invalid in (-1, 0.5, 9007199254740992):
                with self.subTest(value=invalid), self.assertRaises(sqlite3.IntegrityError):
                    db.execute("UPDATE workspace_metadata SET current_import_source_epoch=?", (invalid,))
            db.execute("UPDATE workspace_metadata SET current_import_source_epoch=9007199254740991")
            with self.assertRaises(sqlite3.IntegrityError):
                db.execute("UPDATE workspace_metadata SET previous_epoch_cleanup_pending=9007199254740991")
            db.execute("UPDATE workspace_metadata SET previous_epoch_cleanup_pending=9007199254740990")
            db.execute("UPDATE workspace_metadata SET source_epoch_exhausted=1,previous_epoch_cleanup_pending=9007199254740991")
            self.assertEqual(db.execute("SELECT source_epoch_exhausted,previous_epoch_cleanup_pending FROM workspace_metadata").fetchone(),
                (1, 9007199254740991))
            with self.assertRaises(sqlite3.IntegrityError):
                db.execute("UPDATE workspace_metadata SET current_import_source_epoch=9007199254740990")
            with self.assertRaises(sqlite3.IntegrityError):
                db.execute("UPDATE workspace_metadata SET source_epoch_exhausted=NULL")
            db.execute("UPDATE workspace_metadata SET previous_epoch_cleanup_pending=NULL")
        self.assertTrue(self.validate())

    def test_portable_preferences_exact_fields_and_enum(self):
        migrate(self.probe, self.directory)
        with connect(self.path) as db:
            self.assertEqual({r[1] for r in db.execute("PRAGMA table_info(workspace_preferences)")},
                {"singleton", "timezone", "habit_progress_color", "default_reminder_methods_json", "auto_enable_reminders_on_other_devices", "preferences_revision"})
            with self.assertRaises(sqlite3.IntegrityError):
                db.execute("UPDATE workspace_preferences SET habit_progress_color='#FFFFFF'")
            db.execute("UPDATE workspace_preferences SET default_reminder_methods_json='[\"wechat\"]'")
        # JSON syntax alone is not a typed codec, even on a real SQLite DB.
        with self.assertRaisesRegex(ValueError, "SYNC_PAYLOAD_INVALID"):
            self.validate()

    def test_guest_successor_backup_requires_exact_hash_and_same_reserved_owner(self):
        from protocol_reference import digest, encode
        from storage_reference import WORKSPACE
        migrate(self.probe, self.directory)
        previous = {"source_workspace_id": WORKSPACE, "source_epoch": 0,
            "lineage_id": "aaaaaaaa-aaaa-5aaa-8aaa-aaaaaaaaaaaa", "protected_owner_binding_digest": "a" * 64,
            "source_snapshot_hash": "b" * 64, "reserved_operation_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            "active_batch_id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc", "active_manifest_hash": "c" * 64,
            "begin_client_sequence": 1, "terminal_client_sequence": 3, "state": "active", "lease_revision": 2}
        operation = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
        with connect(self.path) as db:
            db.execute("INSERT INTO guest_import_source_leases VALUES(?,0,?,?,?, ?,NULL,NULL,NULL,NULL,'reserved',3)",
                       (WORKSPACE, previous["lineage_id"], previous["protected_owner_binding_digest"], "d" * 64, operation))
            db.execute("INSERT INTO guest_import_source_lease_replacements VALUES(?,?,0,1,?,?)", (WORKSPACE, operation, encode(previous), digest(previous)))
        self.assertTrue(self.validate())
        with connect(self.path) as db:
            db.execute("UPDATE guest_import_source_lease_replacements SET payload_hash=?", ("0" * 64,))
        with self.assertRaisesRegex(ValueError, "V6_PAYLOAD_HASH_INVALID"):
            self.validate()
        with connect(self.path) as db:
            db.execute("UPDATE guest_import_source_lease_replacements SET payload_hash=?", (digest(previous),))
            db.execute("UPDATE guest_import_source_leases SET protected_owner_binding_digest=?", ("e" * 64,))
        with self.assertRaisesRegex(ValueError, "V6_IMPORT_LEASE_BACKUP_INVALID"):
            self.validate()

    def test_import_mapping_sql_constraints_cover_unpublished_immutability_and_epoch_collision(self):
        # Logical DDL constraints in memory; this is not an encrypted account
        # open or a migration claim. The account-open test above stays closed.
        model = derive()
        with sqlite3.connect(":memory:") as db:
            tables = ("workspace_metadata", "sync_import_mappings", "sync_import_recurrence_families")
            for name in tables:
                db.execute(model["new_tables"][name])
            for name, sql in model["new_triggers"].items():
                if "import_mapping" in name or "import_family" in name or any(name.startswith("guard_" + table + "_") for table in tables[1:]):
                    db.execute(sql)
            db.execute("INSERT INTO workspace_metadata VALUES(1,'workspace','account','account',6,'account_sqlcipher_v1','2026-09-06T00:00:00Z',NULL,NULL,NULL,0)")
            db.execute("INSERT INTO sync_import_mappings VALUES('lineage','source',0,'category','source-id','category','target-id',NULL,NULL,0)")
            for sql in ("UPDATE sync_import_mappings SET target_id='changed'", "DELETE FROM sync_import_mappings",
                        "UPDATE sync_import_mappings SET provenance_version=1"):
                with self.subTest(sql=sql), self.assertRaises(sqlite3.IntegrityError):
                    db.execute(sql)
            with self.assertRaises(sqlite3.IntegrityError):
                db.execute("INSERT INTO sync_import_mappings VALUES('next-lineage','source',1,'category','source-id','category','target-id',NULL,NULL,0)")
            db.execute("INSERT INTO sync_import_mappings VALUES('next-lineage','source',1,'category','source-id','category','new-target',NULL,NULL,0)")
            db.execute("UPDATE sync_import_mappings SET first_published_batch_id='batch',last_published_batch_id='batch',provenance_version=1")
            with self.assertRaises(sqlite3.IntegrityError):
                db.execute("UPDATE sync_import_mappings SET first_published_batch_id='changed',provenance_version=2")
            db.execute("INSERT INTO sync_import_recurrence_families VALUES('lineage','source-family','target-family')")
            with self.assertRaises(sqlite3.IntegrityError):
                db.execute("DELETE FROM sync_import_recurrence_families")


if __name__ == "__main__":
    unittest.main()
