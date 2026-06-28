#!/usr/bin/env bash
# Install this marketplace and all plugins into Claude Code.
# Idempotent: safe to re-run.

set -euo pipefail

MARKETPLACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_NAME="zhipeng-personal"
MANIFEST="$MARKETPLACE_DIR/.claude-plugin/marketplace.json"
EXTERNAL_MANIFEST="$MARKETPLACE_DIR/external-plugins.json"
DISABLED_MANIFEST="$MARKETPLACE_DIR/disabled-plugins.json"

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

marketplace_exists() {
  local name="$1"
  claude plugin marketplace list 2>/dev/null | awk -v name="$name" '$NF == name { found = 1 } END { exit !found }'
}

echo "==> Validating marketplace manifest"
claude plugin validate "$MARKETPLACE_DIR"

echo
echo "==> Registering marketplace: $MARKETPLACE_NAME"
if marketplace_exists "$MARKETPLACE_NAME"; then
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
echo "==> Installing external plugins"
if [[ ! -f "$EXTERNAL_MANIFEST" ]]; then
  echo "    no external plugin manifest found"
else
  jq empty "$EXTERNAL_MANIFEST"

  while IFS=$'\t' read -r external_marketplace_name external_marketplace_source; do
    if marketplace_exists "$external_marketplace_name"; then
      echo "    refreshing marketplace: $external_marketplace_name"
      claude plugin marketplace update "$external_marketplace_name" || true
    else
      echo "    adding marketplace: $external_marketplace_source"
      claude plugin marketplace add "$external_marketplace_source"
    fi

    installed_list="$(claude plugin list 2>/dev/null || true)"
    mapfile -t external_plugins < <(jq -r --arg name "$external_marketplace_name" '.marketplaces[] | select(.name == $name) | .plugins[]' "$EXTERNAL_MANIFEST")

    for name in "${external_plugins[@]}"; do
      ref="$name@$external_marketplace_name"
      if grep -qE "(^|[[:space:]])$name(@|[[:space:]]|$)" <<<"$installed_list"; then
        echo "  [update]  $ref"
        if ! claude plugin update "$ref"; then
          echo "    !! failed to update $ref" >&2
        fi
        continue
      fi
      echo "  [install] $ref"
      if ! claude plugin install "$ref"; then
        echo "    !! failed to install $ref" >&2
      fi
    done
  done < <(jq -r '.marketplaces[] | [.name, .source] | @tsv' "$EXTERNAL_MANIFEST")
fi

echo
echo "==> Applying disabled plugin defaults"
if [[ ! -f "$DISABLED_MANIFEST" ]]; then
  echo "    no disabled plugin manifest found"
else
  jq empty "$DISABLED_MANIFEST"
  mapfile -t disabled_plugins < <(jq -r '.plugins[]' "$DISABLED_MANIFEST")

  for ref in "${disabled_plugins[@]}"; do
    echo "  [disable] $ref"
    disable_output="$(claude plugin disable "$ref" 2>&1)" || {
      if grep -q "already disabled" <<<"$disable_output"; then
        echo "    already disabled"
        continue
      fi
      printf '%s\n' "$disable_output" >&2
      echo "    !! failed to disable $ref" >&2
    }
  done
fi

echo
echo "==> Done. Current plugins:"
claude plugin list
