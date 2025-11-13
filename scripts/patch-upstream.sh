#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQ_FILE="$ROOT_DIR/pgeu-system/tools/devsetup/dev_requirements.txt"

if [[ ! -f "$REQ_FILE" ]]; then
  echo "Error: $REQ_FILE not found. Did you clone pgeu-system/?"
  exit 1
fi

ensure_line() {
  local line="$1"
  if grep -Fxq "$line" "$REQ_FILE"; then
    echo "keep: $line"
  else
    echo "$line" >>"$REQ_FILE"
    echo "add:  $line"
  fi
}

echo "Patching $REQ_FILE ..."

if grep -q '^pycryptodomex==' "$REQ_FILE"; then
  sed -i 's/^pycryptodomex==.*/pycryptodomex==3.19.1/' "$REQ_FILE"
  echo "set:  pycryptodomex==3.19.1"
else
  ensure_line "pycryptodomex==3.19.1"
fi

ensure_line "qrcode==7.4.2"
ensure_line "cairosvg==2.7.1"
ensure_line "PyMuPDF==1.24.9"

echo "Done."
