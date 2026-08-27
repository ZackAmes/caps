#!/usr/bin/env bash
# Redeploy caps contracts to Sepolia and copy the freshly-generated manifest
# into the client so the deployed frontend always targets the live world.
set -euo pipefail

cd "$(dirname "$0")/.."

SOZO="${SOZO:-/home/zack/.asdf/installs/sozo/1.8.6/bin/sozo}"
PROFILE="${PROFILE:-sepolia}"

echo "==> Building + migrating ($PROFILE)..."
cd contracts
"$SOZO" build --profile "$PROFILE"
"$SOZO" --profile "$PROFILE" migrate --wait

echo "==> Copying manifest into client..."
cp "manifest_${PROFILE}.json" ../client/src/lib/dojo/manifest.json

WORLD=$("$SOZO" inspect --profile "$PROFILE" world 2>/dev/null | grep -iE "address" | head -1 || true)
echo "==> Done. World: ${WORLD:-see manifest}"

cd ..
echo "Client manifest synced to: $(python3 -c "import json;print(json.load(open('client/src/lib/dojo/manifest.json'))['world']['address'])")"
