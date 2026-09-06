"""Assertion-preserving dispatch for large discriminated JSON Schema unions.

Only branches whose direct const assertion already fails are omitted. Every
remaining assertion, including oneOf exclusivity, is evaluated by jsonschema.
This is a test-runner optimization, not a new protocol or schema dialect.
"""
from functools import lru_cache

from jsonschema import Draft202012Validator, FormatChecker, ValidationError, validators
from jsonschema._utils import equal
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012


def one_of(validator, alternatives, instance, schema):
    matches = 0
    for alternative in alternatives:
        if isinstance(instance, dict) and isinstance(alternative, dict):
            properties = alternative.get("properties", {})
            impossible = any(name in instance and isinstance(rule, dict) and "const" in rule and
                             not equal(instance[name], rule["const"]) for name, rule in properties.items())
            if impossible:
                continue
        if validator.evolve(schema=alternative).is_valid(instance):
            matches += 1
            if matches == 2:
                break
    if matches != 1:
        yield ValidationError("Expected exactly one matching schema alternative")


DispatchedValidator = validators.extend(Draft202012Validator, {"oneOf": one_of})


@lru_cache(maxsize=1)
def resources():
    # The caller has already checked every original document and ref with the
    # unmodified Draft 2020-12 validator. Removing only each document's dialect
    # annotation keeps evolve on this validator; the explicit specification below
    # preserves all reference, id and JSON Pointer behavior.
    from domain_reference import definitions
    original, _ = definitions()
    copies = {identifier: {key: value for key, value in resource.contents.items() if key != "$schema"}
              for identifier, resource in original.items()}
    registry = Registry().with_resources((identifier, Resource.from_contents(document, default_specification=DRAFT202012))
                                         for identifier, document in copies.items())
    return copies, registry


@lru_cache(maxsize=1024)
def compiled(path):
    from domain_reference import ROOT, read_json
    copies, registry = resources()
    document = read_json(ROOT / "contracts" / path)
    return DispatchedValidator(copies[document["$id"]], registry=registry, format_checker=FormatChecker())


def validate_schema(path, value):
    if not compiled(path).is_valid(value):
        raise ValueError("SYNC_PAYLOAD_INVALID")
