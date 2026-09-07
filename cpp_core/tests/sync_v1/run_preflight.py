"""C0 exit test: a declared freeze is insufficient without the official gate.

Expected exit code is zero. Any source drift or official validation failure
returns nonzero; there is deliberately no allow-drift / fake-success option.
"""
import subprocess
import sys

from contract_input import ROOT, source_drift


def main() -> int:
    drift = source_drift()
    for item in drift:
        print(f"DRIFT {item['path']}\n  expected {item['expected']}\n  actual   {item['actual']}", flush=True)
    result = subprocess.run(
        [sys.executable, str(ROOT / "contracts/run_sync_v1_validation.py")],
        cwd=ROOT, check=False)
    if drift or result.returncode:
        print("C0 BLOCKED: Plan 03 implementation gate has not passed.", flush=True)
        return 1
    print("C0 Contract input gate passed; runtime acceptance remains separate.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
