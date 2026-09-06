"""Disposable JDK signing authority; all private key material stays in memory.

This is an actual test crypto port, not a fake signature or a production signer.
The returned trust material is retained by the test verifier independently of the
untrusted wire proof. Production trust distribution remains the frozen APK path.
"""
import json
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import uuid

from domain_reference import check
from protocol_reference import canonical, digest
from proof_reference import authenticate_typed

HERE = Path(__file__).resolve().parent


class ImportProofVerifier:
    """Read-only verifier using the independently supplied test trust store."""
    def __init__(self, binary, trust):
        self.binary, self.trust = binary, trust

    def verify(self, account, purpose, data, token, claimed_hash):
        try:
            authenticate_typed(self.binary, {"trust_store": self.trust, "locally_revoked_keys": [], "token": token,
                "expected_account_id": account, "expected_purpose": purpose, "claim_data": data, "claimed_hash": claimed_hash})
            return True
        except ValueError:
            return False


class ImportProofAuthority(ImportProofVerifier):
    def __init__(self, binary):
        self.binary = binary
        self.directory = tempfile.TemporaryDirectory(prefix="excellent-calendar-import-public-signer-")
        jdk = Path("A:/Android/AndroidStudio/jbr/bin")
        subprocess.run([str(jdk / "javac.exe"), "-encoding", "UTF-8", "-d", self.directory.name,
            *[str(HERE / name) for name in ("JcsProbe.java", "ProofSignatureProbe.java", "ProofCapsuleProbe.java")]],
            check=True, capture_output=True, timeout=60)
        self.process = subprocess.Popen([str(jdk / "java.exe"), "-cp", self.directory.name, "ProofCapsuleProbe", "--generate-public-golden"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf8", bufsize=1,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        self.lines = queue.Queue()

        def reader():
            for line in self.process.stdout:
                self.lines.put(line)
            self.lines.put(None)

        threading.Thread(target=reader, daemon=True).start()
        keys = self._read()["keys"]
        self.trust = {"schema_version": 1, "keys": sorted(keys, key=lambda row: row["key_id"])}
        self.trust["trust_store_id"] = digest(self.trust)
        self.requests = []

    def _read(self):
        try:
            line = self.lines.get(timeout=30)
        except queue.Empty:
            raise ValueError("PROOF_SIGNER_UNAVAILABLE") from None
        check(line is not None, "PROOF_SIGNER_UNAVAILABLE")
        return json.loads(line)

    def sign(self, account, purpose, data):
        identifier = str(uuid.uuid4())
        self.process.stdin.write(canonical({"id": identifier, "key_slot": 0, "account_id": account, "purpose": purpose, "data": data}).decode() + "\n")
        self.process.stdin.flush()
        signed = self._read()
        check(signed["id"] == identifier, "PROOF_SIGNER_UNAVAILABLE")
        request = {"trust_store": self.trust, "locally_revoked_keys": [], "token": signed["token"], "expected_account_id": account,
            "expected_purpose": purpose, "claim_data": data, "claimed_hash": signed["claimed_hash"]}
        authenticate_typed(self.binary, request)
        self.requests.append(request)
        return signed["token"], signed["claimed_hash"]

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.process.stdout.close()
        self.process.stderr.close()
        self.directory.cleanup()
