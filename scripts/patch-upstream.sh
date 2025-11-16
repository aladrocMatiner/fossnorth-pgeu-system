#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQ_FILE="$ROOT_DIR/pgeu-system/tools/devsetup/dev_requirements.txt"
OAUTH_FILE="$ROOT_DIR/pgeu-system/postgresqleu/oauthlogin/oauthclient.py"

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

echo "Patching OAuth client for Keycloak..."
python - "$OAUTH_FILE" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
code = path.read_text()
if 'oauth_login_keycloak' in code:
    print("keep: keycloak oauth handler")
    sys.exit(0)
snippet = """
\n#
# Keycloak login (generic OIDC)
#\ndef oauth_login_keycloak(request):\n    base = settings.OAUTH['keycloak']['baseurl'].rstrip('/')\n\n    def _keycloak_auth_data(oa):\n        r = oa.get(f'{base}/protocol/openid-connect/userinfo').json()\n        return (\n          r.get('email', ''),\n          r.get('given_name', ''),\n          r.get('family_name', ''),\n        )\n\n    return _login_oauth(\n        request,\n        'keycloak',\n        f'{base}/protocol/openid-connect/auth',\n        f'{base}/protocol/openid-connect/token',\n        ['openid', 'profile', 'email'],\n        _keycloak_auth_data)\n\n"""
marker = "def login_oauth("
idx = code.find(marker)
if idx == -1:
    print("WARN: could not find login_oauth() to inject keycloak handler", file=sys.stderr)
    sys.exit(1)
code = code[:idx] + snippet + code[idx:]
path.write_text(code)
print("add:  keycloak oauth handler")
PY

echo "Done."
