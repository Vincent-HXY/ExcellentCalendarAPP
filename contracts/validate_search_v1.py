#!/usr/bin/env python3
"""Validate the frozen, not-yet-integrated Search V1 Contract package."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import re
import warnings
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urldefrag, urljoin
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

try:
    warnings.filterwarnings(
        "ignore",
        message=r"jsonschema\.RefResolver is deprecated.*",
        category=DeprecationWarning,
    )
    import yaml
    from jsonschema import Draft202012Validator, FormatChecker, RefResolver
except ModuleNotFoundError as error:  # pragma: no cover - environment gate
    raise SystemExit(
        "Verification dependencies are missing. Run run_search_v1_validation.py "
        "to install them in an isolated temporary cache."
    ) from error


CONTRACTS = Path(__file__).resolve().parent
SEARCH = CONTRACTS / "search"
FIXTURES = CONTRACTS / "fixtures" / "search"
TARGET_ORDER = ["event", "habit", "anniversary"]
MAX_KEYWORD_SCALARS = 128
MAX_KEYWORD_UTF8_BYTES = 512
MAX_HISTORY_ITEMS = 20
MAX_PAGE_SIZE = 20
SEARCH_CONTRACT_REVISION = 2

FROZEN_WHITESPACE = (
    set(range(0x0009, 0x000E))
    | {
        0x0020,
        0x0085,
        0x00A0,
        0x1680,
        *range(0x2000, 0x200B),
        0x2028,
        0x2029,
        0x202F,
        0x205F,
        0x3000,
    }
)


def fail(message: str) -> None:
    raise AssertionError(message)


def reject_non_json_constant(value: str) -> None:
    fail(f"Non-JSON numeric constant is forbidden: {value}")


def load_json(path: Path) -> Any:
    try:
        return json.loads(
            path.read_text(encoding="utf-8"), parse_constant=reject_non_json_constant
        )
    except json.JSONDecodeError as error:
        fail(f"Invalid JSON in {path}: {error}")


def load_yaml(path: Path) -> Any:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def collect_schemas() -> tuple[dict[str, Any], dict[str, Path]]:
    schemas: dict[str, Any] = {}
    paths: dict[str, Path] = {}
    for path in CONTRACTS.rglob("*.schema.json"):
        schema = load_json(path)
        schema_id = schema.get("$id")
        if not schema_id:
            fail(f"Schema has no $id: {path}")
        if schema_id in schemas:
            fail(f"Duplicate $id {schema_id}: {paths[schema_id]} and {path}")
        Draft202012Validator.check_schema(schema)
        schemas[schema_id] = schema
        paths[schema_id] = path
    return schemas, paths


def walk_refs(value: Any):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "$ref" and isinstance(child, str):
                yield child
            else:
                yield from walk_refs(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_refs(child)


def validate_ref_closure(
    schemas: dict[str, Any], paths: dict[str, Path]
) -> None:
    for schema_id, schema in schemas.items():
        for ref in walk_refs(schema):
            target, _ = urldefrag(urljoin(schema_id, ref))
            if target.startswith("https://json-schema.org/"):
                continue
            if target not in schemas:
                fail(f"Unclosed $ref {ref} in {paths[schema_id]} -> {target}")


def validate_instance(
    schema_path: Path, instance: Any, schemas: dict[str, Any]
) -> list[str]:
    schema = load_json(schema_path)
    resolver = RefResolver.from_schema(schema, store=schemas)
    validator = Draft202012Validator(
        schema, resolver=resolver, format_checker=FormatChecker()
    )
    return [
        error.message
        for error in sorted(
            validator.iter_errors(instance), key=lambda item: list(item.path)
        )
    ]


def valid_unicode_scalars(value: str) -> bool:
    return not any(0xD800 <= ord(character) <= 0xDFFF for character in value)


def normalize_search_text(value: str) -> str:
    pieces: list[str] = []
    pending_space = False
    for character in value:
        if ord(character) in FROZEN_WHITESPACE:
            if pieces:
                pending_space = True
            continue
        if pending_space:
            pieces.append(" ")
            pending_space = False
        pieces.append(character)
    return "".join(pieces)


def ascii_fold(value: str) -> str:
    return "".join(
        chr(ord(character) + 32) if "A" <= character <= "Z" else character
        for character in value
    )


def canonical_target_order(values: list[str]) -> bool:
    return values == [target for target in TARGET_ORDER if target in values]


def validate_timezone(value: str) -> str | None:
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError):
        return "TIMEZONE_ID_INVALID"
    return None


def semantic_query_request(
    instance: dict[str, Any], case: dict[str, Any]
) -> str | None:
    keyword = instance["keyword"]
    if not valid_unicode_scalars(keyword):
        return "SEARCH_QUERY_INVALID"
    normalized = normalize_search_text(keyword)
    if (
        not normalized
        or len(normalized) > MAX_KEYWORD_SCALARS
        or len(normalized.encode("utf-8")) > MAX_KEYWORD_UTF8_BYTES
    ):
        return "SEARCH_QUERY_INVALID"
    if expected := case.get("expected_normalized_keyword"):
        if normalized != expected:
            return "CONTRACT_VALIDATION_FAILED"
    if error := validate_timezone(instance["timezone"]):
        return error
    if instance["date_from"] is not None:
        start = date.fromisoformat(instance["date_from"])
        end = date.fromisoformat(instance["date_to_exclusive"])
        if end <= start:
            return "SEARCH_QUERY_INVALID"
    target_types = instance["target_types"]
    sections = instance["sections"]
    if any(section["page_size"] != MAX_PAGE_SIZE for section in sections):
        return "SEARCH_QUERY_INVALID"
    section_types = [section["target_type"] for section in sections]
    if not canonical_target_order(target_types):
        return "SEARCH_QUERY_INVALID"
    if len(set(section_types)) != len(section_types):
        return "SEARCH_QUERY_INVALID"
    if not canonical_target_order(section_types):
        return "SEARCH_QUERY_INVALID"
    if any(section not in target_types for section in section_types):
        return "SEARCH_QUERY_INVALID"
    if len(sections) > 1 and (
        section_types != target_types
        or any(section["cursor"] is not None for section in sections)
    ):
        return "SEARCH_QUERY_INVALID"
    if any(section["cursor"] is not None for section in sections) and len(sections) != 1:
        return "SEARCH_QUERY_INVALID"
    return None


MATCHED_FIELDS = {
    "event": ["title", "content", "location", "category_name"],
    "habit": ["title", "description", "category_name"],
    "anniversary": ["title", "note", "category_name"],
}


def semantic_match(item: dict[str, Any]) -> str | None:
    target_type = item["target_type"]
    match = item["match"]
    allowed = MATCHED_FIELDS[target_type]
    fields = match["matched_fields"]
    if match["primary_field"] not in fields:
        return "CONTRACT_VALIDATION_FAILED"
    if any(field not in allowed for field in fields):
        return "CONTRACT_VALIDATION_FAILED"
    if fields != [field for field in allowed if field in fields]:
        return "CONTRACT_VALIDATION_FAILED"
    if "category_name" in fields and item.get("category") is None:
        return "CONTRACT_VALIDATION_FAILED"
    if target_type == "event" and "location" in fields and item.get("location") is None:
        return "CONTRACT_VALIDATION_FAILED"
    snippet = match["snippet"]
    if match["primary_field"] == "title":
        if snippet is not None:
            return "CONTRACT_VALIDATION_FAILED"
    elif snippet is None or snippet["field"] != match["primary_field"]:
        return "CONTRACT_VALIDATION_FAILED"
    if snippet is not None and (
        not valid_unicode_scalars(snippet["text"])
        or len(snippet["text"]) > 200
    ):
        return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_section_response(
    instance: dict[str, Any], _case: dict[str, Any]
) -> str | None:
    items = instance["items"]
    if instance["total_count"] < len(items):
        return "CONTRACT_VALIDATION_FAILED"
    identities = [item["target_id"] for item in items]
    if len(set(identities)) != len(identities):
        return "CONTRACT_VALIDATION_FAILED"
    for item in items:
        if item["target_type"] != instance["target_type"]:
            return "CONTRACT_VALIDATION_FAILED"
        if error := semantic_match(item):
            return error
        if item["target_type"] == "habit":
            start = date.fromisoformat(item["challenge_start_date"])
            end = date.fromisoformat(item["challenge_end_date"])
            occur = date.fromisoformat(item["occur_date"])
            if not start <= occur <= end:
                return "CONTRACT_VALIDATION_FAILED"
        elif item["target_type"] == "anniversary":
            if item["relation"] == "today" and item["days"] != 0:
                return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_query_response(
    instance: dict[str, Any], case: dict[str, Any]
) -> str | None:
    if normalize_search_text(instance["normalized_keyword"]) != instance[
        "normalized_keyword"
    ]:
        return "CONTRACT_VALIDATION_FAILED"
    if error := validate_timezone(instance["timezone"]):
        return error
    section_types = [section["target_type"] for section in instance["sections"]]
    if len(set(section_types)) != len(section_types) or not canonical_target_order(
        section_types
    ):
        return "CONTRACT_VALIDATION_FAILED"
    for section in instance["sections"]:
        if error := semantic_section_response(section, case):
            return error
    return None


def semantic_history(instance: dict[str, Any], _case: dict[str, Any]) -> str | None:
    items = instance["items"]
    if len(items) > MAX_HISTORY_ITEMS:
        return "CONTRACT_VALIDATION_FAILED"
    identity_keys: list[str] = []
    for item in items:
        if (
            not valid_unicode_scalars(item)
            or normalize_search_text(item) != item
            or not item
            or len(item) > MAX_KEYWORD_SCALARS
            or len(item.encode("utf-8")) > MAX_KEYWORD_UTF8_BYTES
        ):
            return "CONTRACT_VALIDATION_FAILED"
        identity_keys.append(ascii_fold(item))
    if len(set(identity_keys)) != len(identity_keys):
        return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_normalization(
    instance: dict[str, Any], _case: dict[str, Any]
) -> str | None:
    for vector in instance.get("vectors", []):
        normalized = normalize_search_text(vector["raw"])
        tokens = normalized.split(" ") if normalized else []
        comparison = [ascii_fold(token) for token in tokens]
        if (
            normalized != vector["normalized"]
            or tokens != vector["tokens"]
            or comparison != vector["comparison_tokens"]
        ):
            return "CONTRACT_VALIDATION_FAILED"
        actual_error = "SEARCH_QUERY_INVALID" if not normalized else None
        if actual_error != vector.get("expected_error"):
            return "CONTRACT_VALIDATION_FAILED"
    return None


def match_tier(query: str, item: dict[str, Any]) -> int | None:
    normalized_query = normalize_search_text(query)
    query_key = ascii_fold(normalized_query)
    tokens = [ascii_fold(token) for token in normalized_query.split(" ")]
    title = ascii_fold(normalize_search_text(item["title"]))
    if title == query_key:
        return 0
    if title.startswith(query_key):
        return 1
    if query_key in title:
        return 2
    if all(token in title for token in tokens):
        return 3
    fields = ["title", "content", "location", "category_name"]
    field_tiers = {"title": 3, "content": 4, "location": 5, "category_name": 6}
    selected_tiers: list[int] = []
    for token in tokens:
        for field in fields:
            raw = item.get(field)
            if raw is not None and token in ascii_fold(normalize_search_text(raw)):
                selected_tiers.append(field_tiers[field])
                break
        else:
            return None
    return max(selected_tiers)


def semantic_matching_ranking(
    instance: dict[str, Any], _case: dict[str, Any]
) -> str | None:
    actual: list[tuple[int, str]] = []
    actual_tiers: dict[str, int] = {}
    for item in instance["items"]:
        tier = match_tier(instance["query"], item)
        if tier is not None:
            actual.append((tier, item["id"]))
            actual_tiers[item["id"]] = tier
    actual.sort()
    if [identity for _, identity in actual] != instance["expected_matching_order"]:
        return "CONTRACT_VALIDATION_FAILED"
    if actual_tiers != instance["expected_tiers"]:
        return "CONTRACT_VALIDATION_FAILED"
    return None


def utc_epoch(value: str) -> int:
    return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())


def semantic_sorting(instance: dict[str, Any], _case: dict[str, Any]) -> str | None:
    relevance = sorted(
        instance["relevance"]["items"],
        key=lambda item: (
            item["tier"],
            item["completion_bucket"],
            item["temporal_bucket"],
            item["distance"],
            -utc_epoch(item["updated_at"]),
            item["id"],
        ),
    )
    if [item["id"] for item in relevance] != instance["relevance"]["expected_order"]:
        return "CONTRACT_VALIDATION_FAILED"
    occur_time = sorted(
        instance["occur_time"]["items"],
        key=lambda item: (
            item["temporal_bucket"],
            item["distance"],
            item["id"],
        ),
    )
    if [item["id"] for item in occur_time] != instance["occur_time"]["expected_order"]:
        return "CONTRACT_VALIDATION_FAILED"
    updated = sorted(
        instance["updated_at"]["items"],
        key=lambda item: (-utc_epoch(item["updated_at"]), item["id"]),
    )
    if [item["id"] for item in updated] != instance["updated_at"]["expected_order"]:
        return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_pagination_boundaries(
    instance: dict[str, Any], _case: dict[str, Any]
) -> str | None:
    page_size = instance.get("page_size")
    if page_size != 20:
        return "CONTRACT_VALIDATION_FAILED"
    for vector in instance.get("vectors", []):
        counts = vector["page_item_counts"]
        flags = vector["has_more"]
        if len(counts) != len(flags) or sum(counts) != vector["total_items"]:
            return "CONTRACT_VALIDATION_FAILED"
        if not counts or flags[-1] or any(count < 0 or count > page_size for count in counts):
            return "CONTRACT_VALIDATION_FAILED"
        if any(flag != (index < len(counts) - 1) for index, flag in enumerate(flags)):
            return "CONTRACT_VALIDATION_FAILED"
        if any(count == 0 and flag for count, flag in zip(counts, flags)):
            return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_cursor_binding(
    instance: dict[str, Any], _case: dict[str, Any], invariants: dict[str, Any]
) -> str | None:
    pagination = invariants["pagination"]
    expected_errors = {
        "malformed_cursor_error": "SEARCH_CURSOR_INVALID",
        "query_mismatch_error": "SEARCH_CURSOR_QUERY_MISMATCH",
        "changed_generation_error": "SEARCH_CURSOR_EXPIRED",
    }
    if instance.get("sort_revision") != pagination["cursor_sort_revision"]:
        return "CONTRACT_VALIDATION_FAILED"
    if instance.get("required_bindings") != pagination["cursor_binds"]:
        return "CONTRACT_VALIDATION_FAILED"
    if any(instance.get(key) != value for key, value in expected_errors.items()):
        return "CONTRACT_VALIDATION_FAILED"
    if instance.get("client_query_generation_is_bound") is not False:
        return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_cursor_authentication(
    instance: dict[str, Any], _case: dict[str, Any], invariants: dict[str, Any]
) -> str | None:
    authentication = invariants["pagination"]["authentication"]
    if instance.get("profile") != authentication.get("profile"):
        return "CONTRACT_VALIDATION_FAILED"
    key = bytes.fromhex(instance["signing_key_hex"])
    if len(key) != authentication.get("key_bytes"):
        return "CONTRACT_VALIDATION_FAILED"
    profiles = {
        "cursor": (
            invariants["pagination"]["cursor_prefix"],
            authentication["cursor_domain_separator"],
        ),
        "snapshot": (
            invariants["snapshot"]["token_prefix"],
            authentication["snapshot_domain_separator"],
        ),
    }
    for vector in instance.get("vectors", []):
        expected_prefix, domain = profiles[vector["token_kind"]]
        actual_error: str | None = None
        try:
            prefix, encoded = vector["token"].split(".", 1)
            if prefix != expected_prefix or "=" in encoded or not re.fullmatch(
                r"[A-Za-z0-9_-]+", encoded
            ):
                raise ValueError("invalid token framing")
            padded = encoded + "=" * (-len(encoded) % 4)
            envelope = base64.b64decode(
                padded.encode("ascii"), altchars=b"-_", validate=True
            )
            if (
                base64.urlsafe_b64encode(envelope).rstrip(b"=").decode("ascii")
                != encoded
            ):
                raise ValueError("non-canonical base64url")
            tag_bytes = authentication["tag_bytes"]
            if len(envelope) <= tag_bytes:
                raise ValueError("missing payload or full tag")
            payload, supplied_tag = envelope[:-tag_bytes], envelope[-tag_bytes:]
            verification_key = bytes.fromhex(
                vector.get("verification_key_hex", instance["signing_key_hex"])
            )
            expected_tag = hmac.new(
                verification_key,
                domain.encode("ascii") + b"\x00" + payload,
                hashlib.sha256,
            ).digest()
            if not hmac.compare_digest(supplied_tag, expected_tag):
                raise ValueError("authentication failed")
            if not payload or payload[0] != authentication["payload_version_byte"]:
                raise ValueError("unsupported payload version")
            if payload.hex() != vector["payload_hex"]:
                raise ValueError("payload mismatch")
        except (KeyError, TypeError, ValueError, base64.binascii.Error):
            actual_error = "SEARCH_CURSOR_INVALID"
        if actual_error != vector.get("expected_error"):
            return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_occurrence_selection(
    instance: dict[str, Any], _case: dict[str, Any]
) -> str | None:
    for vector in instance.get("vectors", []):
        reference = date.fromisoformat(vector["reference_date"])
        start = date.fromisoformat(vector["date_from"])
        end = date.fromisoformat(vector["date_to_exclusive"])
        eligible = []
        for candidate in vector["candidates"]:
            occurrence = date.fromisoformat(candidate["occur_date"])
            if not start <= occurrence < end:
                continue
            is_open = candidate["state"] == "open"
            if not is_open and not vector["include_completed"]:
                continue
            eligible.append(
                (
                    abs((occurrence - reference).days),
                    0 if occurrence >= reference else 1,
                    occurrence,
                    candidate["identity"],
                )
            )
        selected = min(eligible)[3] if eligible else None
        if selected != vector["expected_identity"]:
            return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_request_response_pair(
    instance: dict[str, Any], _case: dict[str, Any], schemas: dict[str, Any]
) -> str | None:
    request_path = FIXTURES / instance["request_instance"]
    response_path = FIXTURES / instance["response_instance"]
    request = load_json(request_path)
    response = load_json(response_path)
    if validate_instance(SEARCH / "search_query_request.schema.json", request, schemas):
        return "CONTRACT_VALIDATION_FAILED"
    if validate_instance(SEARCH / "search_query_response.schema.json", response, schemas):
        return "CONTRACT_VALIDATION_FAILED"
    if semantic_query_request(request, {}) is not None:
        return "CONTRACT_VALIDATION_FAILED"
    if semantic_query_response(response, {}) is not None:
        return "CONTRACT_VALIDATION_FAILED"
    if response["query_generation"] != request["query_generation"]:
        return "CONTRACT_VALIDATION_FAILED"
    if response["normalized_keyword"] != normalize_search_text(request["keyword"]):
        return "CONTRACT_VALIDATION_FAILED"
    if response["timezone"] != request["timezone"]:
        return "CONTRACT_VALIDATION_FAILED"
    requested = [section["target_type"] for section in request["sections"]]
    returned = [section["target_type"] for section in response["sections"]]
    if returned != requested:
        return "CONTRACT_VALIDATION_FAILED"
    for request_section, response_section in zip(request["sections"], response["sections"]):
        if request_section["cursor"] is not None:
            continue
        expected_count = min(request_section["page_size"], response_section["total_count"])
        if len(response_section["items"]) != expected_count:
            return "CONTRACT_VALIDATION_FAILED"
        if response_section["has_more"] != (expected_count < response_section["total_count"]):
            return "CONTRACT_VALIDATION_FAILED"
    return None


def pagination_sequence_error(
    vector: dict[str, Any], fixture: dict[str, Any], schemas: dict[str, Any]
) -> str | None:
    defaults = fixture["defaults"]
    id_sets = fixture["id_sets"]
    page_size = fixture["page_size"]
    expected_total = vector["total_count"]
    cumulative: list[str] = []
    emitted_cursors: set[str] = set()
    previous_next: str | None = None
    for page in vector["pages"]:
        request = page["request"]
        response = page["response"]
        full_request = {
            **fixture["query_template"],
            "query_generation": request["query_generation"],
            "sections": [
                {
                    "target_type": defaults["target_type"],
                    "page_size": page_size,
                    "cursor": request["cursor"],
                }
            ],
        }
        item_ids = id_sets[response["item_ids_ref"]]
        full_items = []
        for identity in item_ids:
            numeric_identity = int(identity.removeprefix("e"))
            item = dict(fixture["event_item_template"])
            item["target_id"] = (
                f"00000000-0000-4000-8000-{numeric_identity:012d}"
            )
            full_items.append(item)
        full_response = {
            **fixture["response_template"],
            "query_generation": response["query_generation"],
            "timezone": response.get("timezone", defaults["timezone"]),
            "evaluated_at": response.get("evaluated_at", defaults["evaluated_at"]),
            "snapshot_token": response.get(
                "snapshot_token", defaults["snapshot_token"]
            ),
            "sections": [
                {
                    "target_type": response.get(
                        "target_type", defaults["target_type"]
                    ),
                    "items": full_items,
                    "total_count": response["total_count"],
                    "has_more": response["has_more"],
                    "next_cursor": response["next_cursor"],
                }
            ],
        }
        if validate_instance(
            SEARCH / "search_query_request.schema.json", full_request, schemas
        ) or validate_instance(
            SEARCH / "search_query_response.schema.json", full_response, schemas
        ):
            return "CONTRACT_VALIDATION_FAILED"
        if (
            semantic_query_request(full_request, {}) is not None
            or semantic_query_response(full_response, {}) is not None
        ):
            return "CONTRACT_VALIDATION_FAILED"
        if request["cursor"] != previous_next:
            return "CONTRACT_VALIDATION_FAILED"
        if response["query_generation"] != request["query_generation"]:
            return "CONTRACT_VALIDATION_FAILED"
        for field in ("target_type", "timezone", "evaluated_at", "snapshot_token"):
            if response.get(field, defaults[field]) != defaults[field]:
                return "CONTRACT_VALIDATION_FAILED"
        if response["total_count"] != expected_total:
            return "CONTRACT_VALIDATION_FAILED"
        expected_page_count = min(page_size, max(0, expected_total - len(cumulative)))
        if len(item_ids) != expected_page_count:
            return "CONTRACT_VALIDATION_FAILED"
        if any(identity in cumulative for identity in item_ids):
            return "CONTRACT_VALIDATION_FAILED"
        cumulative.extend(item_ids)
        expected_has_more = len(cumulative) < expected_total
        if response["has_more"] != expected_has_more:
            return "CONTRACT_VALIDATION_FAILED"
        next_cursor = response["next_cursor"]
        if expected_has_more:
            if (
                next_cursor is None
                or next_cursor == request["cursor"]
                or next_cursor in emitted_cursors
            ):
                return "CONTRACT_VALIDATION_FAILED"
            emitted_cursors.add(next_cursor)
        elif next_cursor is not None or len(cumulative) != expected_total:
            return "CONTRACT_VALIDATION_FAILED"
        previous_next = next_cursor
    if previous_next is not None:
        return "CONTRACT_VALIDATION_FAILED"
    expected_ref = vector.get("expected_ids_ref")
    if expected_ref is not None and cumulative != id_sets[expected_ref]:
        return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_pagination_sequences(
    instance: dict[str, Any], _case: dict[str, Any], schemas: dict[str, Any]
) -> str | None:
    if instance.get("page_size") != MAX_PAGE_SIZE:
        return "CONTRACT_VALIDATION_FAILED"
    for vector in instance.get("vectors", []):
        if pagination_sequence_error(vector, instance, schemas) != vector.get(
            "expected_error"
        ):
            return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_history_revision_boundaries(
    instance: dict[str, Any], _case: dict[str, Any]
) -> str | None:
    maximum = instance.get("maximum_revision")
    if maximum != 9007199254740991:
        return "CONTRACT_VALIDATION_FAILED"
    for vector in instance.get("vectors", []):
        replacement = {
            "revision": vector["current_revision"],
            "items": vector["replacement_items"],
        }
        if semantic_history(replacement, {}) is not None:
            return "CONTRACT_VALIDATION_FAILED"
        changed = vector["replacement_items"] != vector["current_items"]
        if not changed:
            actual_revision = vector["current_revision"]
            actual_write = False
            actual_error = None
        elif vector["current_revision"] == maximum:
            actual_revision = maximum
            actual_write = False
            actual_error = "SEARCH_HISTORY_STORAGE_FAILED"
        else:
            actual_revision = vector["current_revision"] + 1
            actual_write = True
            actual_error = None
        if (
            actual_revision != vector["expected_revision"]
            or actual_write != vector["expected_write"]
            or actual_error != vector["expected_error"]
        ):
            return "CONTRACT_VALIDATION_FAILED"
    return None


def parse_utc(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def resolve_local_boundary(
    local_date: date, zone: ZoneInfo
) -> tuple[datetime, str, datetime]:
    naive = datetime.combine(local_date, time.min)

    def valid_instants(local_value: datetime) -> list[datetime]:
        instants: set[datetime] = set()
        for fold in (0, 1):
            candidate = local_value.replace(tzinfo=zone, fold=fold)
            instant = candidate.astimezone(timezone.utc)
            if instant.astimezone(zone).replace(tzinfo=None) == local_value:
                instants.add(instant)
        return sorted(instants)

    direct = valid_instants(naive)
    if direct:
        return direct[0], "fold" if len(direct) == 2 else "valid", naive
    for seconds_after in range(1, 172801):
        resolved_local = naive + timedelta(seconds=seconds_after)
        resolved = valid_instants(resolved_local)
        if resolved:
            return resolved[0], "gap", resolved_local
    raise ValueError("No valid local instant found within two civil days")


def semantic_event_time(instance: dict[str, Any], _case: dict[str, Any]) -> str | None:
    for vector in instance.get("local_midnight_resolution_vectors", []):
        instant, classification, resolved_local = resolve_local_boundary(
            date.fromisoformat(vector["local_date"]), ZoneInfo(vector["timezone"])
        )
        if (
            classification != vector["expected_classification"]
            or resolved_local.isoformat() != vector["expected_resolved_local"]
            or instant != parse_utc(vector["expected_instant"])
        ):
            return "CONTRACT_VALIDATION_FAILED"
    for vector in instance.get("timed_window_vectors", []):
        zone = ZoneInfo(vector["timezone"])
        start_date = date.fromisoformat(vector["date_from"])
        end_date = date.fromisoformat(vector["date_to_exclusive"])
        start, _, _ = resolve_local_boundary(start_date, zone)
        end, _, _ = resolve_local_boundary(end_date, zone)
        if (
            start != parse_utc(vector["expected_start_at"])
            or end != parse_utc(vector["expected_end_at"])
            or int((end - start).total_seconds()) != vector["expected_duration_seconds"]
        ):
            return "CONTRACT_VALIDATION_FAILED"
        for interval in vector["intervals"]:
            actual_start = parse_utc(interval["start_at"])
            actual_end = parse_utc(interval["end_at"])
            overlaps = actual_start < end and actual_end > start
            if actual_end <= actual_start or overlaps != interval["overlaps"]:
                return "CONTRACT_VALIDATION_FAILED"
    for vector in instance.get("all_day_overlap_vectors", []):
        query_start = date.fromisoformat(vector["date_from"])
        query_end = date.fromisoformat(vector["date_to_exclusive"])
        actual_start = date.fromisoformat(vector["start_date"])
        actual_end = date.fromisoformat(vector["end_date"])
        overlaps = actual_start < query_end and actual_end > query_start
        if actual_end <= actual_start or overlaps != vector["overlaps"]:
            return "CONTRACT_VALIDATION_FAILED"
    for vector in instance.get("status_vectors", []):
        occurrence_state = vector["occurrence_state"]
        if occurrence_state in {"completed", "skipped"}:
            status = occurrence_state
        elif not vector["is_recurring"] and vector["event_status"] == "completed":
            status = "completed"
        elif vector["kind"] == "timed":
            evaluated_at = parse_utc(vector["evaluated_at"])
            start = parse_utc(vector["start_at"])
            end = parse_utc(vector["end_at"])
            status = "pending" if evaluated_at < start else (
                "in_progress" if evaluated_at < end else "overdue"
            )
        else:
            today = parse_utc(vector["evaluated_at"]).astimezone(
                ZoneInfo(vector["timezone"])
            ).date()
            start_date = date.fromisoformat(vector["start_date"])
            end_date = date.fromisoformat(vector["end_date"])
            status = "pending" if today < start_date else (
                "in_progress" if today < end_date else "overdue"
            )
        if status != vector["expected_status"]:
            return "CONTRACT_VALIDATION_FAILED"
    for vector in instance.get("temporal_vectors", []):
        if vector["kind"] == "timed":
            evaluated_at = parse_utc(vector["evaluated_at"])
            start = parse_utc(vector["start_at"])
            end = parse_utc(vector["end_at"])
            if start <= evaluated_at < end:
                bucket, distance_value = 0, 0
            elif evaluated_at < start:
                bucket, distance_value = 0, int((start - evaluated_at).total_seconds())
            else:
                bucket, distance_value = 1, int((evaluated_at - end).total_seconds())
        else:
            today = date.fromisoformat(vector["today"])
            start_date = date.fromisoformat(vector["start_date"])
            end_date = date.fromisoformat(vector["end_date"])
            if start_date <= today < end_date:
                bucket, distance_value = 0, 0
            elif today < start_date:
                bucket, distance_value = 0, (start_date - today).days
            else:
                bucket, distance_value = 1, (today - (end_date - timedelta(days=1))).days
        if bucket != vector["expected_bucket"] or distance_value != vector["expected_distance"]:
            return "CONTRACT_VALIDATION_FAILED"
    return None


def validate_manifest(
    schemas: dict[str, Any], invariants: dict[str, Any]
) -> int:
    handlers = {
        "query_request": semantic_query_request,
        "query_response": semantic_query_response,
        "section_response": semantic_section_response,
        "history": semantic_history,
        "normalization": semantic_normalization,
        "matching_ranking": semantic_matching_ranking,
        "sorting": semantic_sorting,
        "pagination_boundaries": semantic_pagination_boundaries,
        "cursor_binding": lambda value, case: semantic_cursor_binding(
            value, case, invariants
        ),
        "cursor_authentication": lambda value, case: semantic_cursor_authentication(
            value, case, invariants
        ),
        "occurrence_selection": semantic_occurrence_selection,
        "request_response_pair": lambda value, case: semantic_request_response_pair(
            value, case, schemas
        ),
        "pagination_sequences": lambda value, case: semantic_pagination_sequences(
            value, case, schemas
        ),
        "history_revision_boundaries": semantic_history_revision_boundaries,
        "event_time": semantic_event_time,
    }
    manifest = load_json(FIXTURES / "manifest.json")
    if manifest.get("fixture_version") != SEARCH_CONTRACT_REVISION or not manifest.get("cases"):
        fail("Search fixture manifest version/cases are invalid")
    count = 0
    for case in manifest["cases"]:
        count += 1
        instance = load_json(FIXTURES / case["instance"])
        if "schema" in case:
            errors = validate_instance(
                (FIXTURES / case["schema"]).resolve(), instance, schemas
            )
            actual_valid = not errors
            if actual_valid != case["expected_valid"]:
                fail(
                    f"Fixture {case['name']} expected_valid={case['expected_valid']} "
                    f"errors={errors}"
                )
        semantic_check = case.get("semantic_check")
        if semantic_check:
            actual_error = handlers[semantic_check](instance, case)
            if actual_error != case.get("expected_error"):
                fail(
                    f"Fixture {case['name']} semantic error expected "
                    f"{case.get('expected_error')}, got {actual_error}"
                )
    return count


def validate_capabilities(documents: dict[str, Any]) -> None:
    expected_public = {
        "search.query": (
            "search/search_query_request.schema.json",
            "search/search_query_response.schema.json",
            "cpp",
        ),
        "search.get_local_history": (
            "common/native_empty_request.schema.json",
            "search/search_history_response.schema.json",
            "kotlin_local",
        ),
        "search.replace_local_history": (
            "search/replace_search_history_request.schema.json",
            "search/search_history_response.schema.json",
            "kotlin_local",
        ),
    }
    expected_implementation_paths = {
        "search.query": [
            "kotlin_search_handler",
            "search.query native call",
            "cpp_search_query_service",
        ],
        "search.get_local_history": [
            "kotlin_search_handler",
            "atomic_file_search_history_store",
        ],
        "search.replace_local_history": [
            "kotlin_search_handler",
            "atomic_file_search_history_store",
        ],
    }
    methods = documents["method_channels.yaml"]["methods"]
    calls = documents["native_calls.yaml"]["calls"]
    actual_methods = {
        name for name, entry in methods.items() if entry.get("module") == "search"
    }
    actual_calls = {
        name for name, entry in calls.items() if entry.get("module") == "search"
    }
    if actual_methods != set(expected_public):
        fail("Search public capability map drift")
    if actual_calls != {"search.query"}:
        fail("Search native capability map drift or Kotlin-local history leaked into JNI")
    for name, (request, response, implementation) in expected_public.items():
        entry = methods[name]
        if (entry.get("request"), entry.get("result", {}).get("data")) != (
            request,
            response,
        ):
            fail(f"Search public schema drift: {name}")
        if entry.get("implementation") != implementation:
            fail(f"Search public implementation owner drift: {name}")
        if entry.get("implementation_path") != expected_implementation_paths[name]:
            fail(f"Search public implementation path drift: {name}")
        if entry.get("implementation_status") != "integrated" or entry.get(
            "release_status"
        ) != "active":
            fail(f"Search must remain integrated + active after release calibration: {name}")
        if entry.get("event_stream") is not False:
            fail(f"Search methods must not be EventChannels: {name}")
        if entry.get("result", {}).get("envelope") != "common/native_result.schema.json":
            fail(f"Search NativeResult envelope drift: {name}")
    native = calls["search.query"]
    if (native.get("request"), native.get("result", {}).get("data")) != (
        expected_public["search.query"][0],
        expected_public["search.query"][1],
    ):
        fail("Search native query schema drift")
    if (
        native.get("visibility") != "internal"
        or native.get("caller") != "kotlin"
        or native.get("implementation") != "cpp"
        or native.get("implementation_status") != "integrated"
        or native.get("release_status") != "active"
    ):
        fail("Search native query metadata drift")


def validate_errors_and_enums(
    documents: dict[str, Any], schemas: dict[str, Any]
) -> None:
    required_errors = {
        "SEARCH_QUERY_INVALID",
        "SEARCH_CURSOR_INVALID",
        "SEARCH_CURSOR_QUERY_MISMATCH",
        "SEARCH_CURSOR_EXPIRED",
        "SEARCH_HISTORY_CONFLICT",
        "SEARCH_HISTORY_STORAGE_FAILED",
    }
    errors = documents["error_codes.yaml"]["errors"]
    if missing := required_errors - set(errors):
        fail(f"Missing Search errors: {sorted(missing)}")
    for code in required_errors:
        if not {
            "module",
            "message",
            "retryable",
            "boundaries",
            "data_saved_allowed",
        } <= set(errors[code]):
            fail(f"Search error metadata incomplete: {code}")
        if errors[code]["module"] != "search":
            fail(f"Search error module drift: {code}")
    if errors["SEARCH_CURSOR_EXPIRED"]["retryable"] is not True:
        fail("SEARCH_CURSOR_EXPIRED must remain retryable")
    if errors["SEARCH_CURSOR_INVALID"]["retryable"] is not False or errors[
        "SEARCH_CURSOR_QUERY_MISMATCH"
    ]["retryable"] is not False:
        fail("Malformed and mismatched Search cursors must not auto-retry")
    native_codes = set(
        schemas[
            "https://excellent-calendar.local/contracts/common/native_error.schema.json"
        ]["properties"]["code"]["enum"]
    )
    if missing := required_errors - native_codes:
        fail(f"NativeError enum is missing Search codes: {sorted(missing)}")
    expected_enums = {
        "SearchTargetType": TARGET_ORDER,
        "SearchSortBy": ["relevance", "occur_time", "updated_at"],
        "SearchMatchedField": [
            "title",
            "content",
            "description",
            "note",
            "location",
            "category_name",
        ],
        "SearchEventItemStatus": [
            "pending",
            "in_progress",
            "overdue",
            "completed",
            "skipped",
        ],
    }
    enums = documents["enums.yaml"]
    for name, values in expected_enums.items():
        if enums.get(name, {}).get("values") != values:
            fail(f"Search enum drift: {name}")


def validate_invariants(invariants: dict[str, Any]) -> None:
    if (
        invariants.get("version") != SEARCH_CONTRACT_REVISION
        or invariants.get("contract_version") != 2
    ):
        fail("Search invariant version drift")
    if (
        invariants.get("revision_history", {}).get(
            "revision_2_amendment_2026_09_02"
        )
        != "completed_recurring_series_cutoff_aligned_with_calendar_before_release"
    ):
        fail("Search Revision 2 cutoff amendment metadata drift")
    if invariants.get("implementation_status") != "integrated" or invariants.get(
        "release_status"
    ) != "active":
        fail("Search invariants must remain integrated + active")
    if invariants["keyword"]["maximum_unicode_scalar_values"] != MAX_KEYWORD_SCALARS:
        fail("Search keyword scalar limit drift")
    if invariants["keyword"]["maximum_utf8_bytes"] != MAX_KEYWORD_UTF8_BYTES:
        fail("Search keyword UTF-8 limit drift")
    if invariants["history"]["maximum_items"] != MAX_HISTORY_ITEMS:
        fail("Search history limit drift")
    if invariants["pagination"]["default_page_size"] != 20 or invariants[
        "pagination"
    ]["maximum_page_size"] != MAX_PAGE_SIZE:
        fail("Search pagination limits drift")
    if invariants["pagination"].get("fixed_v1_page_size") != MAX_PAGE_SIZE:
        fail("Search V1 page size must remain fixed at 20")
    if invariants["projection"]["section_order"] != TARGET_ORDER:
        fail("Search section order drift")
    expected_contributors = {
        "event": ["events", "recurrence_versions", "event_occurrence_states", "categories"],
        "habit": ["habits", "habit_recurrences", "categories"],
        "anniversary": ["anniversaries", "anniversary_recurrences", "categories"],
    }
    if invariants["snapshot"]["contributing_stores_by_target"] != expected_contributors:
        fail("Search snapshot Store generation contributors drift")
    if invariants["projection"]["first_version_uses_fts"] is not False:
        fail("Search V1 must not activate FTS before the performance gate")
    if not invariants["history"]["excluded_from_android_cloud_backup"] or not invariants[
        "history"
    ]["excluded_from_android_device_transfer"]:
        fail("Device-local Search history must be excluded from backup and transfer")
    if (
        invariants["history"].get("implementation")
        != "kotlin_atomic_file_in_no_backup_directory"
        or invariants["history"].get("directory") != "Context.noBackupFilesDir"
        or invariants["history"].get("shared_preferences_forbidden") is not True
        or invariants["history"].get("writer") != "android.util.AtomicFile"
        or invariants["history"].get(
            "publish_new_in_memory_snapshot_only_after_finishWrite_success"
        )
        is not True
        or invariants["history"].get("durable_write_failure")
        != "SEARCH_HISTORY_STORAGE_FAILED"
    ):
        fail("Search history durability/no-backup strategy drift")
    history_revision = invariants["history"].get("revision", {})
    if (
        history_revision.get("maximum") != 9007199254740991
        or history_revision.get("unchanged_at_maximum_succeeds_without_write")
        is not True
        or history_revision.get(
            "changed_at_maximum_returns_SEARCH_HISTORY_STORAGE_FAILED_without_write"
        )
        is not True
        or history_revision.get(
            "repair_requiring_revision_increment_at_maximum_returns_SEARCH_HISTORY_STORAGE_FAILED_without_write"
        )
        is not True
    ):
        fail("Search history revision exhaustion semantics drift")
    history_recording = invariants["history"].get("recording", {})
    if (
        history_recording.get("debounce_success") != "never"
        or history_recording.get("keyboard_submit_success_including_zero_results")
        != "record_response_normalized_keyword"
        or history_recording.get("keyboard_submit_failure") != "do_not_record"
        or history_recording.get("history_tap")
        != "immediately_move_stored_canonical_keyword_to_front_then_query"
        or history_recording.get("result_open_from_accepted_response")
        != "record_response_normalized_keyword_before_navigation"
    ):
        fail("Search history recording timing drift")
    authentication = invariants["pagination"].get("authentication", {})
    if (
        authentication.get("algorithm") != "HMAC-SHA-256"
        or authentication.get("key_bytes") != 32
        or authentication.get("key_entropy") != "operating_system_csprng"
        or authentication.get("key_persisted") is not False
        or authentication.get("key_rotates_on_native_runtime_process_start") is not True
        or authentication.get("cursor_from_previous_process_returns")
        != "SEARCH_CURSOR_INVALID"
        or authentication.get("constant_time_tag_comparison") is not True
        or authentication.get("wire_token")
        != "<prefix>.<base64url_without_padding(payload_bytes || tag_bytes)>"
        or authentication.get("mac_input")
        != "ascii(domain_separator) || 0x00 || payload_bytes"
        or authentication.get("strict_base64url_canonical_encoding") is not True
        or authentication.get("tag_is_final_32_decoded_bytes") is not True
        or authentication.get("payload_owner") != "cpp_native_runtime_only"
        or authentication.get("dart_and_kotlin_treat_payload_as_opaque") is not True
        or authentication.get("bare_json_fnv_or_calendar_checksum_reuse_forbidden")
        is not True
    ):
        fail("Search cursor authentication profile drift")
    calendar_invariants = load_yaml(
        CONTRACTS / "calendar" / "calendar_query_invariants.yaml"
    )
    calendar_event = calendar_invariants["sections"]["event"]
    if (
        invariants["event"].get("status_projection_source")
        != "contracts/calendar/calendar_query_invariants.yaml#/sections/event/status_projection"
        or invariants["event"].get("status_projection")
        != calendar_event["status_projection"]
    ):
        fail("Search and Calendar Event status projection drift")
    if (
        invariants["event"].get("completed_recurring_series_cutoff_source")
        != "contracts/calendar/calendar_query_invariants.yaml#/sections/event/completed_recurring_series_cutoff"
        or invariants["event"].get("completed_recurring_series_cutoff")
        != calendar_event["completed_recurring_series_cutoff"]
    ):
        fail("Search and Calendar completed recurring-series cutoff drift")
    overlap = invariants["event"].get("date_range_overlap", {})
    selection = invariants["event"].get("selected_occurrence", {})
    if (
        overlap.get("nonexistent_local_boundary")
        != "first_valid_instant_after_gap"
        or overlap.get("ambiguous_local_boundary") != "earlier_instant"
        or overlap.get("timed_overlap_formula")
        != "actual_start_at_lt_query_end_at_and_actual_end_at_gt_query_start_at"
        or overlap.get("all_day_overlap_formula")
        != "actual_start_date_lt_date_to_exclusive_and_actual_end_date_gt_date_from"
        or selection.get(
            "open_status_is_not_a_selection_precedence_when_include_completed_true"
        )
        is not True
        or selection.get("completed_series_without_date_filter")
        != "last_eligible_occurrence_strictly_before_cutoff"
        or selection.get("completed_series_without_eligible_occurrence")
        != "event_not_returned"
        or selection.get("occurrence_state_cannot_restore_cutoff_ineligible_occurrence")
        is not True
        or selection.get("eligibility_applied_before_distance")
        != [
            "hidden_series_and_cancelled_occurrence_removed",
            "completed_recurring_series_cutoff_applied",
            "occurrence_must_overlap_requested_date_window",
            "include_completed_false_removes_completed_and_skipped",
        ]
    ):
        fail("Search Event overlap or nearest-occurrence semantics drift")
    if not re.fullmatch(
        invariants["snapshot"]["token_pattern"],
        "srchsnap1.ABCDEFGHIJKLMNOPQRST",
    ):
        fail("Search snapshot pattern rejects the frozen fixture")
    if not re.fullmatch(
        invariants["pagination"]["cursor_pattern"],
        "srchcur1.ABCDEFGHIJKLMNOPQRST",
    ):
        fail("Search cursor pattern rejects the frozen fixture")


def validate_search_schema_metadata(paths: dict[str, Path]) -> None:
    search_paths = sorted(SEARCH.glob("*.schema.json"))
    if len(search_paths) != 12:
        fail(f"Expected 12 Search schemas, found {len(search_paths)}")
    known_paths = set(paths.values())
    for path in search_paths:
        if path not in known_paths:
            fail(f"Search schema was not collected: {path}")
        schema = load_json(path)
        if schema.get("x-contract-version") != 2:
            fail(f"Search schema contract version drift: {path.name}")
        if schema.get("x-search-contract-revision") != SEARCH_CONTRACT_REVISION:
            fail(f"Search schema revision drift: {path.name}")
        expected_status = (
            "planned" if path.name == "search_index_response.schema.json" else "integrated"
        )
        if schema.get("x-implementation-status") != expected_status:
            fail(
                f"Search schema status drift: {path.name} must be {expected_status}"
            )


def validate_native_result_examples(schemas: dict[str, Any]) -> None:
    response = load_json(FIXTURES / "query_response_three_types.valid.json")
    success = {
        "ok": True,
        "data": response,
        "error": None,
        "contract_version": 2,
        "request_id": "search-fixture-success",
    }
    errors = validate_instance(CONTRACTS / "common/native_result.schema.json", success, schemas)
    if errors:
        fail(f"Valid Search NativeResult success rejected: {errors}")
    failure = {
        "ok": False,
        "data": None,
        "error": {
            "code": "SEARCH_CURSOR_EXPIRED",
            "message": "cursor expired",
            "details": None,
            "retryable": True,
        },
        "contract_version": 2,
        "request_id": "search-fixture-failure",
    }
    errors = validate_instance(CONTRACTS / "common/native_result.schema.json", failure, schemas)
    if errors:
        fail(f"Valid Search NativeResult failure rejected: {errors}")


def validate_additive_compatibility(documents: dict[str, Any]) -> None:
    methods = documents["method_channels.yaml"]["methods"]
    calls = documents["native_calls.yaml"]["calls"]
    expected_event_search = (
        "event/search_event_request.schema.json",
        "event/event_list_response.schema.json",
    )
    for mapping in (methods, calls):
        entry = mapping["event.search"]
        actual = (entry.get("request"), entry.get("result", {}).get("data"))
        if actual != expected_event_search:
            fail("Search V1 must not mutate legacy event.search")


def main() -> int:
    schemas, paths = collect_schemas()
    validate_ref_closure(schemas, paths)
    documents = {
        name: load_yaml(CONTRACTS / name)
        for name in (
            "method_channels.yaml",
            "native_calls.yaml",
            "error_codes.yaml",
            "enums.yaml",
        )
    }
    invariants = load_yaml(SEARCH / "search_query_invariants.yaml")
    validate_search_schema_metadata(paths)
    validate_invariants(invariants)
    validate_capabilities(documents)
    validate_errors_and_enums(documents, schemas)
    validate_additive_compatibility(documents)
    validate_native_result_examples(schemas)
    fixture_count = validate_manifest(schemas, invariants)
    print(
        "Search V1 contract validation passed: "
        f"schemas={len(schemas)} fixtures={fixture_count} public_methods=3 "
        "native_calls=1 status=integrated+active fts=deferred"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
