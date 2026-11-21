#!/bin/bash
# Usage: deploy-cloudkit-schema.sh <container-id>
# cktool imports only into Development; the CloudKit Console deploys it to Production.
set -euo pipefail

CONTAINER="${1:?usage: deploy-cloudkit-schema.sh <container-id>}"
# The team is this Mac's signer, read from the gitignored Signing.local.xcconfig unless given.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM_ID="${ONECAST_TEAM_ID:-$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$ROOT/Signing.local.xcconfig" 2>/dev/null)}"
[ -n "$TEAM_ID" ] || { echo "Set ONECAST_TEAM_ID or DEVELOPMENT_TEAM in Signing.local.xcconfig" >&2; exit 1; }
SCHEMA="$ROOT/Config/CloudKit/schema.ckdb"

xcrun cktool import-schema --team-id "$TEAM_ID" --container-id "$CONTAINER" --environment development \
    --validate --file "$SCHEMA"
echo "✓ $CONTAINER (development) has the iCloud Sync schema; deploy it to Production in the CloudKit Console"
