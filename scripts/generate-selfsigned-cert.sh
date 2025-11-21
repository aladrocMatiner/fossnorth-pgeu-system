#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-new.foss-north.se}"
CERT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/certs"
KEY_FILE="${CERT_DIR}/${DOMAIN}.key"
CRT_FILE="${CERT_DIR}/${DOMAIN}.crt"

mkdir -p "${CERT_DIR}"

echo "Generating self-signed certificate for ${DOMAIN} in ${CERT_DIR}"
openssl req -x509 -nodes -days 365 \
  -newkey rsa:4096 \
  -keyout "${KEY_FILE}" \
  -out "${CRT_FILE}" \
  -subj "/CN=${DOMAIN}" \
  -addext "subjectAltName=DNS:${DOMAIN}"

echo "--> Key: ${KEY_FILE}"
echo "--> Cert: ${CRT_FILE}"
