#!/bin/sh
set -e

CA_NAME="${CA_NAME:-EM_DV_TLS_CA_-_G3B}"
DOMAIN="${DOMAIN:-google.com}"
DAYS="${DAYS:-365}"

CA_CERT="/ca/pem/${CA_NAME}.pem"
CA_KEY="/ca/private/${CA_NAME}.pem"
OUTPUT_DIR="/etc/nginx/certs"

if [ ! -f "$CA_CERT" ]; then
    echo "Error: CA certificate not found at $CA_CERT"
    exit 1
fi

if [ ! -f "$CA_KEY" ]; then
    echo "Error: CA private key not found at $CA_KEY"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "==> Configuring SSL for '${DOMAIN}' using CA: '${CA_NAME}'"

SERVER_KEY="${OUTPUT_DIR}/server.key"
if [ ! -f "$SERVER_KEY" ]; then
    echo "--> Generating server private key"
    openssl ecparam -name prime256v1 -genkey -noout -out "$SERVER_KEY"
fi

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

SERVER_CSR="/tmp/server.csr"
openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" -config "$EXT_FILE"

SERVER_CERT="${OUTPUT_DIR}/server.crt"
echo "--> Signing certificate with ${CA_NAME}"
openssl x509 -req \
    -in "$SERVER_CSR" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAserial "${OUTPUT_DIR}/${CA_NAME}.srl" \
    -CAcreateserial \
    -out "$SERVER_CERT" \
    -days "$DAYS" \
    -sha384 \
    -extfile "$EXT_FILE" \
    -extensions v3_ext

FULLCHAIN="${OUTPUT_DIR}/fullchain.crt"
# If the CA is direct-signed by emSign Root TLS CA - G3, append the cross-certificate to the trusted root (emSign ECC Root CA - G3)
CROSS_CERT="/ca/pem/emSign_Root_TLS_CA_-_G3_cross_ECC.pem"
if [ -f "$CROSS_CERT" ] && ! echo "$CA_NAME" | grep -q "_cross"; then
    echo "--> Appending cross-certificate for emSign Root TLS CA - G3 -> emSign ECC Root CA - G3"
    cat "$SERVER_CERT" "$CA_CERT" "$CROSS_CERT" > "$FULLCHAIN"
else
    cat "$SERVER_CERT" "$CA_CERT" > "$FULLCHAIN"
fi

cp "$CA_CERT" "${OUTPUT_DIR}/ca.crt"

echo "--> SSL certificates ready."
exec nginx -g "daemon off;"
