# -*- coding: utf-8 -*-
"""Versleutelt de databestanden van de gebouwde tool, zodat ze zonder wachtwoord
onleesbaar zijn — óók bij directe download. Draai NA `npm run build`, op de map
`dashboard/dist/data`.

    python deploy/encrypt_data.py "dynamo2026"
    python deploy/encrypt_data.py "dynamo2026" pad/naar/dist/data   # afwijkende map

Elk .json/.geojson-bestand wordt AES-256-GCM-versleuteld naar `<bestand>.enc`
(bytes: iv(12) || ciphertext+tag) en het plaintext-bestand wordt VERWIJDERD.
De sleutel wordt met PBKDF2-HMAC-SHA256 (200k iteraties) uit het wachtwoord
afgeleid. Een publiek `enc-meta.json` bevat alleen de salt + iteraties + een
controleblok (geen geheim) waarmee de app een fout wachtwoord kan herkennen.

De browser ontsleutelt met dezelfde parameters via de Web Crypto API
(`dashboard/src/lib/crypto.ts`). Vereist een HTTPS-context in productie.

LET OP: dit beschermt tegen wie het wachtwoord niet kent, maar de versleutelde
bestanden zijn downloadbaar — kies dus een niet-triviaal wachtwoord (offline
brute-force blijft theoretisch mogelijk).
"""
import base64
import json
import os
import sys
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes

ITERATIONS = 200_000
CHECK_PLAINTEXT = b"dynamo-monitor-ok"  # ontsleutelt correct <=> juist wachtwoord


def derive_key(password: str, salt: bytes) -> bytes:
    kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=ITERATIONS)
    return kdf.derive(password.encode("utf-8"))


def enc_blob(key: bytes, data: bytes) -> bytes:
    iv = os.urandom(12)
    return iv + AESGCM(key).encrypt(iv, data, None)


def main() -> int:
    if len(sys.argv) < 2:
        print('Gebruik: python deploy/encrypt_data.py "<wachtwoord>" [pad/naar/dist/data]')
        return 2
    password = sys.argv[1]
    root = Path(sys.argv[2]) if len(sys.argv) > 2 else (
        Path(__file__).resolve().parent.parent / "dashboard" / "dist" / "data"
    )
    if not root.is_dir():
        print(f"FOUT: datamap niet gevonden: {root}\n"
              f"Draai eerst `npm run build` in dashboard/.")
        return 1
    if (root / "enc-meta.json").exists():
        print(f"FOUT: {root} lijkt al versleuteld (enc-meta.json bestaat). "
              f"Herbouw eerst een schone dist/ (`npm run build`).")
        return 1

    salt = os.urandom(16)
    key = derive_key(password, salt)

    targets = [p for p in root.rglob("*") if p.suffix in (".json", ".geojson")]
    for p in targets:
        p.with_suffix(p.suffix + ".enc").write_bytes(enc_blob(key, p.read_bytes()))
        p.unlink()  # plaintext verwijderen — anders lekt de data alsnog

    (root / "enc-meta.json").write_text(json.dumps({
        "v": 1,
        "salt": base64.b64encode(salt).decode(),
        "iter": ITERATIONS,
        "check": base64.b64encode(enc_blob(key, CHECK_PLAINTEXT)).decode(),
    }), encoding="utf-8")

    print(f"OK: {len(targets)} databestanden versleuteld in {root}; "
          f"plaintext verwijderd; enc-meta.json geschreven.")
    print("De app toont nu automatisch een ontgrendelscherm (encryptie-modus gedetecteerd).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
