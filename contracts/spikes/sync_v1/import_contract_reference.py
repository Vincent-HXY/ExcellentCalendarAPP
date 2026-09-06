"""Exact import digest, item ordering and typed canonical publication rules."""
import copy

from bootstrap_reference import CAPS
from counter_reference import MAXIMUM, integer
from domain_reference import check, definitions, validate_schema
from protocol_reference import canonical, digest

ITEM_FIELDS = ("target_type", "target_id", "operation_type", "payload")
PUBLISH_FIELDS = ("import_publish_group_id", "import_lineage_id", "import_batch_id", "source_workspace_id", "source_epoch",
    "manifest_hash", "mapping_digest", "begin_server_sequence", "commit_server_sequence", "total_chunk_count", "total_item_count", "publish_digest")


def item_projection(mutation):
    check(mutation["operation_type"] in {"import_put", "import_delete"}, "SYNC_SEQUENCE_ROUTE_MISMATCH")
    return {name: copy.deepcopy(mutation[name]) for name in ITEM_FIELDS}


def source_key(item):
    return item["target_type"], item["payload"].get("source_id", "portable_preferences")


def utf16_key(item):
    return tuple(value.encode("utf-16-be") for value in source_key(item))


def mapping_rows(items):
    rows = [{"target_type": row["target_type"], "source_id": row["payload"]["source_id"], "target_id": row["target_id"]}
        for row in items if row["target_type"] != "user_preferences"]
    rows.sort(key=lambda row: (row["target_type"].encode("utf-16-be"), row["source_id"].encode("utf-16-be")))
    check(len({(row["target_type"], row["source_id"]) for row in rows}) == len(rows) and
        len({(row["target_type"], row["target_id"]) for row in rows}) == len(rows), "IMPORT_DUPLICATE_IDENTITY")
    return rows


def manifest_digest(manifest, items):
    value = {key: item for key, item in manifest.items() if key != "manifest_hash"}
    value["ordered_item_hashes"] = [{"ordinal": ordinal, "item_hash": digest(item_projection(item))} for ordinal, item in enumerate(items)]
    return digest(value)


def make_manifest(source, epoch, source_hash, items):
    counts = {name: 0 for name in definitions()[1]["targets"] if name not in {"user_preferences", "account_profile"}}
    portable = 0
    for item in items:
        if item["target_type"] == "user_preferences":
            portable += 1
        else:
            check(item["target_type"] in counts, "SYNC_TARGET_UNSUPPORTED")
            counts[item["target_type"]] += 1
    value = {"source_workspace_id": source, "source_epoch": epoch, "source_snapshot_hash": source_hash,
        "target_counts": counts, "portable_preferences_count": portable, "total_item_count": len(items),
        "total_canonical_bytes": sum(len(canonical(item_projection(item))) for item in items),
        "mapping_digest": digest(mapping_rows(items))}
    value["manifest_hash"] = manifest_digest(value, items)
    validate_schema("sync/sync_import_manifest.schema.json", value)
    validate_manifest(value, items)
    return value


def validate_manifest(manifest, items):
    validate_schema("sync/sync_import_manifest.schema.json", manifest)
    check([utf16_key(item) for item in items] == sorted(set(utf16_key(item) for item in items)), "IMPORT_DUPLICATE_IDENTITY")
    counts = {name: 0 for name in manifest["target_counts"]}
    portable = 0
    for item in items:
        if item["target_type"] == "user_preferences":
            portable += 1
        else:
            check(item["target_type"] in counts, "IMPORT_REFERENCE_INVALID")
            counts[item["target_type"]] += 1
    check(len(items) == manifest["total_item_count"] and counts == manifest["target_counts"] and portable == manifest["portable_preferences_count"], "IMPORT_REFERENCE_INVALID")
    check(sum(len(canonical(item_projection(item))) for item in items) == manifest["total_canonical_bytes"], "SYNC_IMPORT_CAPACITY_EXCEEDED")
    check(digest(mapping_rows(items)) == manifest["mapping_digest"] and manifest_digest(manifest, items) == manifest["manifest_hash"], "IMPORT_REFERENCE_INVALID")


def publication(binding, items, first_sequence, publish_group_id):
    """Partition real typed images; never split a typed item or trim the graph."""
    integer(first_sequence)
    check(first_sequence >= 1, "SYNC_SERVER_SEQUENCE_EXHAUSTED")
    batches, batch, item_bytes = [], [], 0
    # Construct with worst-case safe counters so crossing a digit boundary
    # cannot make a previously sized chunk exceed its hard cap.
    shell = {"kind": "import_publish_chunk", "server_sequence": MAXIMUM, "import_publish_group_id": publish_group_id,
        "chunk_ordinal": MAXIMUM, "first_item_ordinal": MAXIMUM, "payload_hash": "0" * 64}
    empty_bytes = len(canonical({**shell, "items": []}))
    for item in items:
        if item["kind"] not in {"created", "resolved"} and item["target_type"] != "user_preferences":
            provenance = item.get("import_provenance")
            check(provenance is not None and all(provenance[name] == binding[name] for name in
                ("import_lineage_id", "source_workspace_id", "source_epoch")), "IMPORT_LINEAGE_MISMATCH")
        size = len(canonical(item))
        # Canonical arrays contribute exactly one comma between adjacent items.
        # Count each item once instead of serializing every growing prefix.
        if len(batch) == 500 or empty_bytes + item_bytes + size + len(batch) > CAPS["import_chunk_hard_bytes"]:
            check(bool(batch), "SYNC_CHANGE_GROUP_TOO_LARGE")
            batches.append(batch)
            batch = [item]
            item_bytes = size
            check(empty_bytes + size <= CAPS["import_chunk_hard_bytes"], "SYNC_CHANGE_GROUP_TOO_LARGE")
        else:
            batch.append(item)
            item_bytes += size
    if batch:
        batches.append(batch)
    check(first_sequence + len(batches) + 1 <= MAXIMUM, "SYNC_SERVER_SEQUENCE_EXHAUSTED")
    shared = {"import_publish_group_id": publish_group_id, **{name: binding[name] for name in
        ("import_lineage_id", "import_batch_id", "source_workspace_id", "source_epoch", "manifest_hash", "mapping_digest")},
        "begin_server_sequence": first_sequence, "commit_server_sequence": first_sequence + len(batches) + 1,
        "total_chunk_count": len(batches), "total_item_count": len(items), "publish_digest": digest(items)}
    result = [{"kind": "import_publish_begin", "server_sequence": first_sequence, **shared}]
    position = 0
    for ordinal, values in enumerate(batches):
        chunk = {"kind": "import_publish_chunk", "server_sequence": first_sequence + ordinal + 1,
            "import_publish_group_id": publish_group_id, "chunk_ordinal": ordinal, "first_item_ordinal": position, "items": values}
        chunk["payload_hash"] = digest(chunk)
        result.append(chunk)
        position += len(values)
    result.append({"kind": "import_publish_commit", "server_sequence": shared["commit_server_sequence"], **shared})
    for item in result:
        validate_schema("sync/sync_import_publish_item.schema.json", item)
    return result


def validate_publication(messages):
    check(len(messages) >= 2 and messages[0]["kind"] == "import_publish_begin" and messages[-1]["kind"] == "import_publish_commit", "IMPORT_PUBLISH_INCOMPLETE")
    begin, commit = messages[0], messages[-1]
    validate_schema("sync/sync_import_publish_item.schema.json", begin)
    validate_schema("sync/sync_import_publish_item.schema.json", commit)
    check(all(begin[name] == commit[name] for name in PUBLISH_FIELDS), "IMPORT_PUBLISH_INCOMPLETE")
    check(begin["commit_server_sequence"] - begin["begin_server_sequence"] + 1 == len(messages) and
        all(row["server_sequence"] == begin["begin_server_sequence"] + index for index, row in enumerate(messages)), "IMPORT_PUBLISH_INCOMPLETE")
    check(len(messages) == begin["total_chunk_count"] + 2, "IMPORT_PUBLISH_INCOMPLETE")
    items = []
    for ordinal, chunk in enumerate(messages[1:-1]):
        check(chunk["kind"] == "import_publish_chunk" and chunk["import_publish_group_id"] == begin["import_publish_group_id"] and
            chunk["chunk_ordinal"] == ordinal and chunk["first_item_ordinal"] == len(items), "IMPORT_PUBLISH_INCOMPLETE")
        check(digest({key: value for key, value in chunk.items() if key != "payload_hash"}) == chunk["payload_hash"], "SYNC_PAYLOAD_HASH_MISMATCH")
        check(len(canonical(chunk)) <= CAPS["import_chunk_hard_bytes"], "SYNC_CHANGE_GROUP_TOO_LARGE")
        items.extend(chunk["items"])
    check(len(items) == begin["total_item_count"] and digest(items) == begin["publish_digest"], "IMPORT_PUBLISH_INCOMPLETE")
    for chunk in messages[1:-1]:
        validate_schema("sync/sync_import_publish_item.schema.json", chunk)
    return items
