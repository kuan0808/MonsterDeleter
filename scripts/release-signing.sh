#!/bin/sh
# Ephemeral hosted-runner keychain. Never run with shell tracing enabled.
set -eu
set +x
case "${1:-}" in
  cleanup)
    [ ! -f "$RUNNER_TEMP/release.keychain-db" ] || security delete-keychain "$RUNNER_TEMP/release.keychain-db"
    rm -f "$RUNNER_TEMP/release.p12"
    exit 0 ;;
  check|setup) ;;
  *) echo 'usage: release-signing.sh check|setup|cleanup' >&2; exit 1 ;;
esac
missing=""
for name in DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD CODESIGN_IDENTITY NOTARY_APPLE_ID NOTARY_TEAM_ID NOTARY_PASSWORD; do
  value="$(printenv "$name" || true)"
  [ -n "$value" ] || missing="$missing $name"
done
[ -z "$missing" ] || { echo "missing release credentials:$missing" >&2; exit 1; }
case "$CODESIGN_IDENTITY" in
  'Developer ID Application:'*) ;;
  *) echo 'stable release requires a Developer ID Application identity' >&2; exit 1 ;;
esac
[ "$1" != check ] || exit 0
[ "${GITHUB_ACTIONS:-}" = true ] || { echo 'setup is for ephemeral GitHub runners only' >&2; exit 1; }
umask 077
keychain="$RUNNER_TEMP/release.keychain-db"
password="$(openssl rand -hex 32)"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
python3 - <<'PY'
import base64, os
from pathlib import Path
(Path(os.environ['RUNNER_TEMP']) / 'release.p12').write_bytes(
    base64.b64decode(os.environ['DEVELOPER_ID_P12_BASE64'], validate=True))
PY
security import "$RUNNER_TEMP/release.p12" -P "$DEVELOPER_ID_P12_PASSWORD" -k "$keychain" -T /usr/bin/codesign > /dev/null
rm -f "$RUNNER_TEMP/release.p12"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" > /dev/null
security list-keychains -d user -s "$keychain" login.keychain-db
xcrun notarytool store-credentials monsterdeleter-release --keychain "$keychain" \
  --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" > /dev/null
{
  echo 'NOTARY_PROFILE=monsterdeleter-release'
  echo "NOTARY_KEYCHAIN=$keychain"
} >> "$GITHUB_ENV"
