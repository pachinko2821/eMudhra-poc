#!/bin/bash
set -euo pipefail

# Select CA base name from argument or env var, defaulting to EM_DV_TLS_CA_-_G3B
CA_NAME="${1:-${CA_NAME:-EM_DV_TLS_CA_-_G3B}}"
DOMAIN="${DOMAIN:-google.com}"
DAYS="${DAYS:-365}"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CA_CERT="${BASE_DIR}/pem/${CA_NAME}.pem"
CA_KEY="${BASE_DIR}/private/${CA_NAME}.pem"
OUTPUT_DIR="${BASE_DIR}/certs"

if [ ! -f "$CA_CERT" ]; then
    echo "Error: CA certificate not found at $CA_CERT"
    exit 1
fi

if [ ! -f "$CA_KEY" ]; then
    echo "Error: CA private key not found at $CA_KEY"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "==> Generating SSL certificate for '${DOMAIN}' signed by '${CA_NAME}'"

# 1. Generate server private key (EC prime256v1 or P-256)
SERVER_KEY="${OUTPUT_DIR}/server.key"
if [ ! -f "$SERVER_KEY" ]; then
    echo "--> Generating server private key: $SERVER_KEY"
    openssl ecparam -name prime256v1 -genkey -noout -out "$SERVER_KEY"
fi

# 2. Create OpenSSL config for CSR and extensions (SAN)
EXT_FILE="${OUTPUT_DIR}/openssl-san.cnf"
cat <<EOF > "$EXT_FILE"
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
CN = ${DOMAIN}
O = Test Organization
C = US

[req_ext]
subjectAltName = @alt_names

[v3_ext]
authorityKeyIdentifier = keyid,issuer
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = *.${DOMAIN}
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF

# 3. Generate Certificate Signing Request (CSR)
SERVER_CSR="${OUTPUT_DIR}/server.csr"
echo "--> Generating CSR: $SERVER_CSR"
openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" -config "$EXT_FILE"

# 4. Sign the certificate with the selected CA
SERVER_CERT="${OUTPUT_DIR}/server.crt"
echo "--> Signing certificate with CA (${CA_NAME})"
openssl x509 -req \
    -in "$SERVER_CSR" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out "$SERVER_CERT" \
    -days "$DAYS" \
    -sha384 \
    -extfile "$EXT_FILE" \
    -extensions v3_ext

# 5. Create fullchain bundle (server cert + CA cert) and copy active CA cert
FULLCHAIN="${OUTPUT_DIR}/fullchain.crt"
cat "$SERVER_CERT" "$CA_CERT" > "$FULLCHAIN"
cp "$CA_CERT" "${OUTPUT_DIR}/ca.crt"

echo "--> Certificate generation complete in $OUTPUT_DIR:"
echo "    - Server Key:       $SERVER_KEY"
echo "    - Server Cert:      $SERVER_CERT"
echo "    - Fullchain Cert:   $FULLCHAIN"
echo "    - CA Cert:          ${OUTPUT_DIR}/ca.crt (from ${CA_NAME})"

