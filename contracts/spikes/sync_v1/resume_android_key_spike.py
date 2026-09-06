"""Resume a recorded, disposable APK run after an OEM installation prompt.

The original report and APK hashes establish ownership. Every completed phase
is journaled locally before the next mutation, including the synthetic wrapper.
No product package, system setting, or backup transport is touched.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--sdk", type=Path, default=Path("A:/Android/sdk"))
    parser.add_argument("--report", type=Path, default=HERE / "android_key_spike_result.json")
    args = parser.parse_args()
    scratch = args.scratch.resolve(strict=True)
    report_path = args.report
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if Path(report["scratch"]).resolve() != scratch or not scratch.name.startswith("excellent-calendar-android-keystore-"):
        raise ValueError("resume path does not belong to the recorded build")
    for path, expected in report["source_sha256"].items():
        if path == Path(__file__).relative_to(ROOT).as_posix():
            continue  # Host-only resume parser; APK sources remain immutable.
        if hashlib.sha256((ROOT / path).read_bytes().replace(b"\r\n", b"\n")).hexdigest() != expected:
            raise ValueError("tested source changed: " + path)
    manifest = ET.parse(scratch / "AndroidManifest-1.xml").getroot()
    package = manifest.attrib["package"]
    if not re.fullmatch(r"com\.excellentcalendar\.contractspike\.sync\.s[0-9a-f]{16}", package):
        raise ValueError("not an isolated generated package")
    apks = {}
    for version in (1, 2):
        for abi in ("arm64-v8a", "armeabi-v7a"):
            key = "apk_" + str(version) + "_" + abi
            suffix = "-" + abi if key in report["builds"] else ""
            key = key if suffix else "apk_" + str(version)
            apk = scratch / ("keystore-spike-" + str(version) + suffix + ".apk")
            if hashlib.sha256(apk.read_bytes()).hexdigest() != report["builds"][key]["sha256"]:
                raise ValueError("resume APK changed")
            apks[version, abi] = apk
    journal_path = scratch / "device_phase_checkpoint.json"
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    if journal["package"] != package or journal["serial"] != args.serial:
        raise ValueError("checkpoint identity mismatch")
    adb = [args.sdk / "platform-tools/adb.exe", "-s", args.serial]
    component = package + "/com.excellentcalendar.contractspike.SyncStorageInstrumentation"

    def save():
        pending = journal_path.with_suffix(".pending")
        pending.write_text(json.dumps(journal, indent=2) + "\n", encoding="utf-8")
        pending.replace(journal_path)

    def run(command, *, binary=False, input=None, timeout=180):
        process = subprocess.run([str(item) for item in command], capture_output=True, input=input,
            **({} if binary else {"encoding": "utf-8", "errors": "replace"}), timeout=timeout)
        if process.returncode:
            detail = "" if binary else (process.stdout + process.stderr)[-1000:]
            raise RuntimeError("isolated device command failed: " + str(command[0]) + ": " + str(process.returncode) + ": " + detail)
        return process.stdout if binary else process.stdout.strip()

    def installed_version():
        rows = run(adb + ["shell", "pm", "list", "packages", package]).splitlines()
        if not rows:
            return None
        if rows != ["package:" + package]:
            raise ValueError("package lookup is ambiguous")
        location = run(adb + ["shell", "pm", "path", package])
        if not location.startswith("package:/data/app/") or "\n" in location:
            raise ValueError("unexpected installed APK location")
        digest = run(adb + ["shell", "sha256sum", location.removeprefix("package:")]).split()[0]
        for key, built in report["builds"].items():
            if key.startswith("apk_") and digest == built["sha256"]:
                version = int(key.split("_")[1])
                return version
        raise ValueError("installed package is not the recorded test APK; leave it unchanged")

    def install(version, abi, replace=False):
        existing = installed_version()
        pending = {"version": version, "abi": abi, "replace": replace}
        # An OEM dialog can outlive adb. Only a journaled attempt may be adopted.
        if existing == version and journal.get("pending_install") == pending:
            journal.pop("pending_install", None)
            save()
            return
        if existing is not None and (not replace or existing != 1):
            raise ValueError("unexpected package state before installation")
        if replace and existing is None:
            raise ValueError("missing package before upgrade")
        journal["pending_install"] = pending
        save()
        output = run(adb + ["install", "--abi", abi, *(["-r"] if replace else []), apks[version, abi]])
        if "Success" not in output.splitlines() or installed_version() != version:
            raise ValueError("installation did not complete")
        journal.pop("pending_install", None)
        save()

    def uninstall():
        if installed_version() is not None:
            if run(adb + ["uninstall", package]) != "Success":
                raise ValueError("isolated uninstall failed")
        if installed_version() is not None:
            raise ValueError("isolated package still installed")

    def instrument(phase, **extras):
        command = adb + ["shell", "am", "instrument", "-w", "-e", "phase", phase]
        for key, value in extras.items():
            command += ["-e", key, value]
        output = run(command + [component])
        fields = dict(re.findall(r"^INSTRUMENTATION_RESULT: ([a-z0-9_]+)=(.*)$", output, re.M))
        if fields.get("status") != "PASS" or "INSTRUMENTATION_CODE: 0" not in output:
            raise ValueError("instrumentation " + phase + " failed: " + output[-2400:])
        cases = json.loads(fields["cases"])
        if not cases or len(set(cases)) != len(cases):
            raise ValueError("missing or duplicate cases")
        return {"passed": True, "cases": cases, "installation_id": fields["installation_id"],
                "process_id": int(fields["process_id"]), "is_64_bit": fields["is_64_bit"] == "true"}

    report.setdefault("prior_attempt_errors", []).extend(report.pop("errors", []))
    report["errors"] = []
    report["passed"] = False
    report["build_only"] = False
    report["scope"] = "disposable Android APK Keystore/JNI/native SQLCipher and packaged backup configuration"
    try:
        for abi in ("arm64-v8a", "armeabi-v7a"):
            if abi not in report["device"]["abi"].split(","):
                continue
            item = journal["consumers"].setdefault(abi, {})
            if "initial" not in item:
                install(1, abi)
                item["initial"] = instrument("initial")
                save()
            initial = item["initial"]
            if initial["is_64_bit"] != (abi == "arm64-v8a"):
                raise ValueError("actual process ABI differs")
            wrapper_file = scratch / ("synthetic-wrapper-" + abi + ".bin")
            if not wrapper_file.exists():
                wrapper_file.write_bytes(run(adb + ["exec-out", "run-as", package, "cat", "no_backup/wrapped-key.bin"], binary=True))
            wrapper = wrapper_file.read_bytes()
            if len(wrapper) != 136 or wrapper[:8] != b"ECSKEY01":
                raise ValueError("binary wrapper layout")
            item["binary_wrapper_bytes"] = len(wrapper)
            if "process_restart" not in item:
                run(adb + ["shell", "am", "force-stop", package])
                item["process_restart"] = instrument("reopen")
                save()
            reopened = item["process_restart"]
            if reopened["process_id"] == initial["process_id"] or reopened["installation_id"] != initial["installation_id"]:
                raise ValueError("process restart continuity")
            if "apk_upgrade" not in item:
                install(2, abi, replace=True)
                item["apk_upgrade"] = instrument("upgraded")
                save()
            if item["apk_upgrade"]["installation_id"] != initial["installation_id"]:
                raise ValueError("upgrade continuity")
            if "crypto_destroy" not in item:
                item["crypto_destroy"] = instrument("destroy")
                save()
            if "uninstalled_before_reinstall" not in item:
                uninstall()
                item["uninstalled_before_reinstall"] = True
                save()
            if "reinstall" not in item:
                install(2, abi)
                item["reinstall"] = instrument("reinstalled", previous_installation=initial["installation_id"])
                save()
            if "restored_ciphertext" not in item:
                run(adb + ["shell", "-T", "run-as", package, "dd", "bs=1", "count=136", "of=no_backup/restored-wrapper.bin"], binary=True, input=wrapper, timeout=20)
                item["restored_ciphertext"] = instrument("restored-ciphertext")
                save()
            if "cleanup_confirmed" not in item:
                uninstall()
                item["cleanup_confirmed"] = True
                save()
        if "arm64-v8a" not in journal["consumers"]:
            raise ValueError("actual arm64 evidence absent")
        report["passed"] = True
        report["test_package_absent_after_run"] = installed_version() is None
    except Exception as error:
        # Preserve state for the human-mediated OEM prompt; never silently start
        # a different package or repeat a destructive lifecycle phase.
        report["errors"].append(str(error))
    report["consumers"] = journal["consumers"]
    report["source_sha256"][Path(__file__).relative_to(ROOT).as_posix()] = hashlib.sha256(Path(__file__).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "completed_phases": {abi: list(item) for abi, item in report["consumers"].items()}, "errors": report["errors"]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
