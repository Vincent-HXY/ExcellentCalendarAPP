"""Build and execute C++, Java, Kotlin and Dart Contract assertion consumers."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from cross_language_schema_reference import bundle

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
JDK = Path("A:/Android/AndroidStudio/jbr/bin")
DART = Path("A:/flutter/flutter/bin/cache/dart-sdk/bin/dart.exe")
CACHE = Path("C:/Users/vincent/.gradle/caches/modules-2/files-2.1")


def jar(group, artifact, version):
    paths = sorted((CACHE / group / artifact / version).glob("*/*.jar"))
    paths = [path for path in paths if path.name == artifact + "-" + version + ".jar"]
    if len(paths) != 1:
        raise ValueError("Existing pinned Kotlin dependency is not uniquely available: " + artifact)
    return paths[0]


def main():
    report = {"spike_version": 1, "passed": False, "consumers": {}, "errors": [], "production_implemented": False,
        "all_fixture_families_verified": False, "scope": "All fixed fixture control records round trip in four parsers; typed schema, Native v2/v3 compatibility and JCS boundary assertions are separate. Stateful and OS expectations use their owner runners.",
        "shared_primitive": "Java and Kotlin use the same already audited JVM JSON/JCS primitive; assertion consumers are separate"}
    source_paths = {Path(__file__), HERE / "cross_language_schema_reference.py", HERE / "fixture_roundtrip_oracle.cjs", HERE / "jcs_probe.cpp", HERE / "JcsProbe.java", HERE / "sha256_probe.hpp",
        ROOT / "contracts/fixtures/sync/v1/manifest.json"}
    source_paths.update(HERE / name for name in ("domain_reference.py", "schema_validation_reference.py", "protocol_reference.py", "counter_reference.py"))
    source_paths.update(HERE / name for name in ("SchemaProbeJson.java", "SchemaJavaProbe.java", "SchemaKotlinProbe.kt", "schema_cpp_probe.cpp", "schema_dart_probe.dart"))
    source_paths.update(ROOT / "contracts/fixtures/sync/v1" / name for name in ("protocol_vectors.json", "capability_vectors.json", "target_vectors.json"))
    try:
        value, paths = bundle()
        source_paths.update(paths)
        expected = ["VALID\t" + case["canonical_utf8_hex"] if case["valid"] else "REJECT" for case in value["cases"]]
        report["case_count"] = len(expected)
        report["schema_documents"] = len(paths)
        report["assertion_nodes"] = len(value["nodes"])
        report["case_ids"] = [case["id"] for case in value["cases"]]
        report["fixture_transport_ids"] = [case["fixture_id"] for case in value["cases"] if case.get("role") == "fixture_transport_only"]
        report["fixture_transport_families"] = sorted({case["family"] for case in value["cases"] if case.get("role") == "fixture_transport_only"})
        report["all_fixed_fixture_transport_verified"] = False
        report["scope_counts"] = {role: sum(case.get("role", "schema_boundary") == role for case in value["cases"])
            for role in sorted({case.get("role", "schema_boundary") for case in value["cases"]})}
        with tempfile.TemporaryDirectory(prefix="excellent-calendar-four-language-schema-") as temporary:
            scratch = Path(temporary)
            input_path = scratch / "assertions.json"
            input_path.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")), encoding="utf8")
            report["derived_assertion_graph_sha256"] = hashlib.sha256(input_path.read_bytes()).hexdigest()

            def run(command):
                process = subprocess.run([str(item) for item in command], capture_output=True, encoding="utf8", errors="strict", timeout=240)
                if process.returncode:
                    raise ValueError(Path(str(command[0])).name + ": " + process.stdout[-1800:] + process.stderr[-3400:])
                return process.stdout

            def check(name, output):
                rows = output.splitlines()
                if rows != expected:
                    failures = [case["id"] for index, case in enumerate(value["cases"]) if index >= len(rows) or rows[index] != expected[index]]
                    raise ValueError(name + " differs from reviewed bytes/validity: " + ",".join(failures[:20]))
                report["consumers"][name] = {"passed": True, "cases": len(rows), "output_sha256": hashlib.sha256(output.encode()).hexdigest()}
                print(json.dumps({"consumer": name, **report["consumers"][name]}), flush=True)

            classes = scratch / "classes"
            classes.mkdir()
            run([JDK / "javac.exe", "-encoding", "UTF-8", "-d", classes, HERE / "JcsProbe.java", HERE / "SchemaProbeJson.java", HERE / "SchemaJavaProbe.java"])
            check("java21", run([JDK / "java.exe", "-cp", classes, "SchemaJavaProbe", input_path]))
            cpp = scratch / "schema.exe"
            run(["D:/mingw/mingw64/bin/g++.exe", "-std=c++17", "-O2", HERE / "schema_cpp_probe.cpp", "-o", cpp])
            check("cpp_windows", run([cpp, input_path]))
            compiler = jar("org.jetbrains.kotlin", "kotlin-compiler-embeddable", "2.2.20")
            pom = next(compiler.parent.parent.glob("*/*.pom"))
            ns = {"m": "http://maven.apache.org/POM/4.0.0"}
            dependencies = [compiler]
            for dependency in ET.parse(pom).findall("./m:dependencies/m:dependency", ns):
                dependencies.append(jar(*[dependency.find("m:" + name, ns).text for name in ("groupId", "artifactId", "version")]))
            dependencies.append(jar("org.jetbrains", "annotations", "13.0"))
            stdlib = jar("org.jetbrains.kotlin", "kotlin-stdlib", "2.2.20")
            runtime = os.pathsep.join(map(str, (classes, stdlib)))
            run([JDK / "java.exe", "-cp", os.pathsep.join(map(str, dependencies)), "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler",
                "-no-stdlib", "-no-reflect", "-jvm-target", "17", "-classpath", runtime, "-d", classes, HERE / "SchemaKotlinProbe.kt"])
            check("kotlin_jvm_2_2_20", run([JDK / "java.exe", "-cp", runtime, "SchemaKotlinProbeKt", input_path]))
            report["kotlin_existing_dependencies_sha256"] = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in dependencies}
            check("dart", run([DART, HERE / "schema_dart_probe.dart", input_path]))
        report["passed"] = len(report["consumers"]) == 4
        report["all_fixed_fixture_transport_verified"] = report["passed"]
    except Exception as error:
        report["errors"].append(type(error).__name__ + ": " + str(error))
    report["source_sha256"] = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() for path in sorted(source_paths)}
    (HERE / "cross_language_schema_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({"passed": report["passed"], "cases": report.get("case_count"), "errors": report["errors"]}), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
