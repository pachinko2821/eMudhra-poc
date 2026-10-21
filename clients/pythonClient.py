import os
import sys
import socket
import requests

urls = [
    "https://dv-g3b-emudhra.we-have-a-problem.com/",
    "https://dv-g3b-aaa-emudhra.we-have-a-problem.com/"
]

py_ver = sys.version.split()[0]
print(
    f"--- [Python {py_ver}] Starting External Domain Checks (using requests) ---")

for url in urls:
    print(f"[Python {py_ver}] Requesting: {url}")
    try:
        resp = requests.get(url, timeout=10)
        print(f"[Python {py_ver}] -> Status: {resp.status_code} ({url})")
    except Exception as e:
        print(
            f"[Python {py_ver}] -> FAILED: {type(e).__name__} ({e}) for {url}")

print(f"--- [Python {py_ver}] External Checks Done ---\n")

domain = os.environ.get("DOMAIN", "google.com")
print(f"[Python {py_ver}] Testing local Nginx connection to https://{domain} (resolved via /etc/hosts)...")

# Verify DNS resolution in container
try:
    resolved_ip = socket.gethostbyname(domain)
    print(f"[Python {py_ver}] /etc/hosts resolved {domain} -> {resolved_ip}")
except Exception as e:
    print(f"[Python {py_ver}] DNS lookup failed for {domain}: {e}")

try:
    resp = requests.get(f"https://{domain}/", timeout=10)
    print(f"[Python {py_ver}] SUCCESS! Python requests verified certificate for https://{domain}/. Status: {resp.status_code}. Text: {resp.text}")
except Exception as e:
    print(
        f"[Python {py_ver}] FAILED! Python requests Error: {type(e).__name__} - {e}")
