"""Check original-civil reconstruction against the unchanged compiled Core."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from build_occurrence_identity_fixtures import derive, FIXTURE

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]


def main():
    parser=argparse.ArgumentParser(__doc__); parser.add_argument("--gxx",default="D:/mingw/mingw64/bin/g++.exe"); args=parser.parse_args()
    scratch=Path(tempfile.mkdtemp(prefix="excellent-calendar-occurrence-identity-")); binary=scratch/"occurrence.exe"
    report={"spike_version":1,"passed":False,"scope":"actual Core v2 recurrence/TZDB lookup and remapped UUID identity",
            "production_v6_writer_implemented":False,"legacy_v1_conversion_verified":False,"native_v3_wide_revision_runtime_verified":False,
            "cases":[],"errors":[]}
    libraries=[ROOT/"cpp_core/build-ninja"/name for name in ("libexcellent_calendar_core.a","libexcellent_calendar_date_tz.a","libexcellent_calendar_sqlite.a")]
    try:
        fixed=derive()
        if json.loads(FIXTURE.read_text(encoding="utf-8"))!=fixed: raise ValueError("fixture drift")
        command=[args.gxx,"-std=c++17","-O2","-finput-charset=UTF-8","-I",str(ROOT/"cpp_core/include"),"-I",str(ROOT/"cpp_core/third_party"),str(HERE/"occurrence_identity_probe.cpp")]
        command += [str(path) for path in libraries]+["-lbcrypt","-lole32","-pthread","-o",str(binary)]
        compiled=subprocess.run(command,capture_output=True,encoding="utf-8",errors="replace",timeout=180)
        if compiled.returncode: raise ValueError("Core-linked probe build failed: "+compiled.stderr[-2400:])
        run=subprocess.run([str(binary),str(ROOT/"cpp_core/third_party/tzdata/2026c")],
            input="\n".join(json.dumps(case["input"],ensure_ascii=False,separators=(",",":")) for case in fixed["cases"])+"\n",
            capture_output=True,encoding="utf-8",timeout=60,check=True)
        lines=run.stdout.splitlines()
        if len(lines)!=len(fixed["cases"]): raise ValueError("Core probe omitted a case")
        for case,line in zip(fixed["cases"],lines):
            actual=None if line=="REJECT" else json.loads(line)
            passed=actual==case["expected"]["result"]
            report["cases"].append({"id":case["id"],"passed":passed,"actual":actual})
            if not passed: report["errors"].append(case["id"]+": actual output differs from fixed expectation")
        report["actual_output_sha256"]=hashlib.sha256(run.stdout.replace("\r\n","\n").encode()).hexdigest()
        report["core_library_sha256"]={path.relative_to(ROOT).as_posix():hashlib.sha256(path.read_bytes()).hexdigest() for path in libraries}
        report["binary_sha256"]=hashlib.sha256(binary.read_bytes()).hexdigest(); report["passed"]=not report["errors"]
    except Exception as error: report["errors"].append(str(error))
    sources=[Path(__file__),HERE/"occurrence_identity_probe.cpp",HERE/"build_occurrence_identity_fixtures.py",FIXTURE,
             ROOT/"contracts/identity.yaml",ROOT/"cpp_core/src/application/recurrence_service.cpp",
             ROOT/"cpp_core/src/infrastructure/time/tzdb_local_time_resolver.cpp",ROOT/"cpp_core/include/excellent_calendar/domain/recurrence.hpp",
             *sorted((ROOT/"cpp_core/third_party/tzdata/2026c").glob("*"))]
    report["source_sha256"]={path.relative_to(ROOT).as_posix():hashlib.sha256(path.read_bytes().replace(b"\r\n",b"\n")).hexdigest() for path in sources if path.is_file()}
    (HERE/"occurrence_identity_spike_result.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"passed":report["passed"],"cases":len(report["cases"]),"errors":report["errors"]}))
    return 0 if report["passed"] else 1


if __name__=="__main__": raise SystemExit(main())
