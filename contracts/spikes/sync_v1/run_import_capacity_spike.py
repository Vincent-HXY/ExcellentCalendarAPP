"""Run actual 20k/50k mixed typed import capacity checks in disposable stores."""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import sys
import tempfile
import time

from import_capacity_reference import combined_graph
from import_contract_reference import validate_publication
from import_staging_reference import ImportStagingStore, build_initial_batch
from protocol_reference import canonical, digest, mutation_hash

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
S = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
D = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"


def sources(roots=None):
    """Follow local imports, including imports inside functions, before running.

    Unrelated new reference modules must not invalidate this workload. Every
    transitive dependency actually used by this runner remains hash-bound.
    """
    pending, found = list(roots or [Path(__file__).resolve()]), set()
    while pending:
        path = pending.pop()
        if path in found:
            continue
        found.add(path)
        if path.suffix in {".cpp", ".hpp", ".h"}:
            for included in re.findall(r'^\s*#\s*include\s*"([^"]+)"', path.read_text(encoding="utf8"), re.MULTILINE):
                candidate = (path.parent / included).resolve()
                if candidate.is_relative_to(ROOT) and candidate.is_file():
                    pending.append(candidate)
        if path.suffix != ".py":
            continue
        for node in ast.walk(ast.parse(path.read_text(encoding="utf8"))):
            names = [node.module] if isinstance(node, ast.ImportFrom) else [row.name for row in node.names] if isinstance(node, ast.Import) else []
            for name in names:
                if name:
                    for folder in (HERE, ROOT / "contracts/tests", ROOT / "contracts"):
                        candidate = folder / (name.split(".")[0] + ".py")
                        if candidate.is_file():
                            pending.append(candidate)
                            break
            if isinstance(node, ast.Constant) and isinstance(node.value, str) and node.value.endswith((".cpp", ".hpp", ".java", ".h", ".py", ".cjs", ".dart", ".kt")):
                candidate = HERE / Path(node.value).name
                if candidate.is_file():
                    pending.append(candidate)
    found.update((ROOT / "contracts").rglob("*.schema.json"))
    found.update((ROOT / "contracts").rglob("*.yaml"))
    found.update((ROOT / "contracts/fixtures/sync/v1").glob("*.json"))
    found.update(ROOT / name for name in ("contracts/validate_sync_v1.py", "contracts/sync/sync_field_registry.yaml",
        "contracts/sync/sync_protocol_invariants.yaml", "contracts/sync/sync_import_protocol.yaml"))
    return sorted(found)


def hashes(paths):
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() for path in paths}


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--counts", nargs="+", type=int, default=[20000, 50000])
    parser.add_argument("--report", type=Path, default=HERE / "import_capacity_spike_result.json")
    args = parser.parse_args()
    report = {"spike_version": 1, "passed": False, "counts": [], "errors": [], "production_implemented": False,
        "scope": "Actual mixed typed graphs, manifest, SQLite staging and complete publication; not Android v6 performance or four-language owners"}
    source_paths = sources()
    source_before = hashes(source_paths)
    try:
        for count in args.counts:
            started = time.monotonic()
            records = combined_graph(count)
            print(json.dumps({"phase": "graph_validated", "facts": len(records), "seconds": round(time.monotonic() - started, 3)}), flush=True)
            batch = build_initial_batch(A, S, 0, records)
            manifest = batch[0]["payload"]["manifest"]
            del records
            with tempfile.TemporaryDirectory(prefix="excellent-calendar-import-capacity-") as temporary:
                server = ImportStagingStore(Path(temporary) / "server.db", account_id=A)
                server.register(D)
                last_progress = time.monotonic()
                for position in range(0, len(batch), 100):
                    messages = [{"mutation": mutation, "payload_hash": mutation_hash(mutation)} for mutation in batch[position:position + 100]]
                    result = server.exchange(D, 0, messages)
                    if any(row["status"] not in {"staged", "accepted"} for row in result):
                        raise ValueError("Typed mixed graph import rejected")
                    if time.monotonic() - last_progress >= 20:
                        print(json.dumps({"phase": "staged", "facts": count, "through_client_sequence": position + len(messages)}), flush=True)
                        last_progress = time.monotonic()
                if result[-1]["status"] != "accepted":
                    raise ValueError("No accepted terminal commit")
                with server.connect() as db:
                    messages = [json.loads(row[0]) for row in db.execute("SELECT payload FROM import_publication_lines ORDER BY sequence")]
                    observed_facts = db.execute("SELECT count(*) FROM facts").fetchone()[0]
                    receipt_count = db.execute("SELECT count(*) FROM receipts").fetchone()[0]
                    mapping_count = db.execute("SELECT count(*) FROM import_mapping").fetchone()[0]
                images = validate_publication(messages)
                if not (observed_facts == mapping_count == len(images) == count and receipt_count == count + 2):
                    raise ValueError("Capacity graph, mapping or receipt count differs")
                report["counts"].append({"input_business_facts": count, "expanded_import_items": manifest["total_item_count"],
                    "target_counts": manifest["target_counts"], "canonical_bytes": manifest["total_canonical_bytes"],
                    "published_facts": observed_facts, "mapping_count": mapping_count, "actual_receipts": receipt_count,
                    "publish_chunks": len(messages) - 2, "maximum_chunk_canonical_bytes": max(len(canonical(line)) for line in messages[1:-1]),
                    "publication_digest": digest(images), "seconds": round(time.monotonic() - started, 3), "passed": True})
                print(json.dumps(report["counts"][-1]), flush=True)
        report["passed"] = args.counts == [20000, 50000] and all(row["passed"] for row in report["counts"])
    except Exception as error:
        report["errors"].append(type(error).__name__ + ": " + str(error))
    # The candidate can only be used with the same actual implementation and
    # schema set. A change requires rerunning this workload, not editing hashes.
    report["source_sha256"] = hashes(source_paths)
    if report["source_sha256"] != source_before:
        report["passed"] = False
        report["errors"].append("Source changed during workload; rerun required")
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({"passed": report["passed"], "errors": report["errors"]}), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
