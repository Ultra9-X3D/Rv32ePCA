#!/usr/bin/env python3
"""Check that released RTL, constraints and submission artifacts are unchanged."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
expected = json.loads((root / "SHA256SUMS.json").read_text())
failures = []
for name, digest in expected.items():
    path = root / name
    actual = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
    if actual != digest:
        failures.append(name)
if failures:
    raise SystemExit("Hash mismatch: " + ", ".join(failures))
print(f"PASS: {len(expected)} ws_0002 source and submission hashes")
