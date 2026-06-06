#!/usr/bin/env bash
# Install this marketplace and all plugins into Claude Code.
# Idempotent: safe to re-run.

set -euo pipefail

MARKETPLACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_NAME="zhipeng-personal"
MANIFEST="$MARKETPLACE_DIR/.claude-plugin/marketplace.json"

if ! command -v claude >/dev/null 2>&1; then
  echo "error: 'claude' CLI not found in PATH" >&2
  exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "error: manifest not found at $MANIFEST" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: 'jq' is required" >&2
  exit 1
fi

echo "==> Validating marketplace manifest"
claude plugin validate "$MARKETPLACE_DIR"

echo
echo "==> Registering marketplace: $MARKETPLACE_NAME"
if claude plugin marketplace list 2>/dev/null | grep -q "^$MARKETPLACE_NAME\b"; then
  echo "    already registered, refreshing"
  claude plugin marketplace update "$MARKETPLACE_NAME" || true
else
  claude plugin marketplace add "$MARKETPLACE_DIR"
fi

echo
echo "==> Installing plugins"
installed_list="$(claude plugin list 2>/dev/null || true)"
mapfile -t plugins < <(jq -r '.plugins[].name' "$MANIFEST")

for name in "${plugins[@]}"; do
  ref="$name@$MARKETPLACE_NAME"
  if grep -qE "(^|[[:space:]])$name(@|[[:space:]]|$)" <<<"$installed_list"; then
    echo "  [skip]    $ref (already installed)"
    continue
  fi
  echo "  [install] $ref"
  if ! claude plugin install "$ref"; then
    echo "    !! failed to install $ref" >&2
  fi
done

echo
echo "==> Done. Current plugins:"
claude plugin list
