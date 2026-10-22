#!/bin/sh
set -e

# CA_NAME selects the intermediate CA (e.g. EM_DV_TLS_CA_-_G3B, EM_OV_TLS_CA_-_G3C, etc.)
CA_NAME="${CA_NAME:-EM_DV_TLS_CA_-_G3B}"
DOMAIN="${DOMAIN:-google.com}"
DAYS="${DAYS:-365}"

# ROOT_TYPE options:
#   "emudhra" / "ecc" : Cross-signs to 'emSign ECC Root CA - G3' (same as https://dv-g3b-emudhra.we-have-a-problem.com/)
#   "aaa"             : Cross-signs to 'AAA Certificate Services' (same as https://dv-g3b-aaa-emudhra.we-have-a-problem.com/)
ROOT_TYPE="${ROOT_TYPE:-emudhra}"

BASE_CA_NAME=$(echo "$CA_NAME" | sed 's/_cross$//')

OUTPUT_DIR="/etc/nginx/certs"
mkdir -p "$OUTPUT_DIR"

echo "==> Configuring SSL for '${DOMAIN}' using CA: '${BASE_CA_NAME}' and Root Type: '${ROOT_TYPE}'"

# Locate private key
CA_KEY="/ca/private/${BASE_CA_NAME}.pem"
if [ ! -f "$CA_KEY" ]; then
    echo "Error: CA private key not found at $CA_KEY"
    exit 1
fi

# Locate intermediate certificate based on ROOT_TYPE
if [ "$ROOT_TYPE" = "aaa" ]; then
    CA_CERT="/ca/pem/${BASE_CA_NAME}_cross.pem"
    if [ ! -f "$CA_CERT" ]; then
        echo "Error: AAA cross-signed certificate not found at $CA_CERT"
        exit 1
    fi
else
    # Default to emudhra ECC root path
    CA_CERT="/ca/pem/${BASE_CA_NAME}.pem"
    if [ ! -f "$CA_CERT" ]; then
        echo "Error: Certificate not found at $CA_CERT"
        exit 1
    fi
fi

# 1. Generate server key if not present
SERVER_KEY="${OUTPUT_DIR}/server.key"
if [ ! -f "$SERVER_KEY" ]; then
    echo "--> Generating server private key"
    openssl ecparam -name prime256v1 -genkey -noout -out "$SERVER_KEY"
fi

# 2. OpenSSL CSR configuration
EXT_FILE="/tmp/openssl-san.cnf"
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

# 3. Create CSR
SERVER_CSR="/tmp/server.csr"
openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" -config "$EXT_FILE"

# 4. Sign leaf certificate with intermediate CA
SERVER_CERT="${OUTPUT_DIR}/server.crt"
echo "--> Signing certificate with ${BASE_CA_NAME}"
openssl x509 -req \
    -in "$SERVER_CSR" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAserial "${OUTPUT_DIR}/${BASE_CA_NAME}.srl" \
    -CAcreateserial \
    -out "$SERVER_CERT" \
    -days "$DAYS" \
    -sha384 \
    -extfile "$EXT_FILE" \
    -extensions v3_ext

FULLCHAIN="${OUTPUT_DIR}/fullchain.crt"

# 5. Build fullchain according to the chosen Root CA path:
if [ "$ROOT_TYPE" = "aaa" ]; then
    echo "--> [Mode: AAA] Chaining directly to 'AAA Certificate Services'"
    cat "$SERVER_CERT" "$CA_CERT" > "$FULLCHAIN"
else
    echo "--> [Mode: eMudhra ECC] Chaining to 'emSign ECC Root CA - G3' via intermediate cross-cert"
    CROSS_ECC="/ca/pem/emSign_Root_TLS_CA_-_G3_cross_ECC.pem"
    if [ -f "$CROSS_ECC" ]; then
        # Ensure only the single direct intermediate is taken if file has multiple
        openssl x509 -in "$CA_CERT" > "/tmp/inter.pem"
        cat "$SERVER_CERT" "/tmp/inter.pem" "$CROSS_ECC" > "$FULLCHAIN"
    else
        cat "$SERVER_CERT" "$CA_CERT" > "$FULLCHAIN"
    fi
fi

cp "$CA_CERT" "${OUTPUT_DIR}/ca.crt"

echo "--> SSL fullchain ready."
exec nginx -g "daemon off;"
