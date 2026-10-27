#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# create-game.sh — Scaffold a new game from the _template
#
# Usage:
#   ./scripts/create-game.sh <game-id> "<Game Display Name>"
#
# Example:
#   ./scripts/create-game.sh idle-empire "Idle Empire"
#
# This will:
#   1. Copy games/_template → games/<game-id>
#   2. Replace all GAME_ID, GAME_DISPLAY_NAME placeholders
#   3. Print next steps
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

GAME_ID="${1:-}"
GAME_NAME="${2:-}"

if [[ -z "$GAME_ID" || -z "$GAME_NAME" ]]; then
  echo "Usage: $0 <game-id> \"<Game Display Name>\""
  echo "Example: $0 idle-empire \"Idle Empire\""
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$ROOT_DIR/games/_template"
TARGET_DIR="$ROOT_DIR/games/$GAME_ID"

if [[ -d "$TARGET_DIR" ]]; then
  echo "Error: $TARGET_DIR already exists"
  exit 1
fi

echo "🎮 Creating game: $GAME_NAME ($GAME_ID)"

# ── Copy template ─────────────────────────────────────────────────────────────
cp -r "$TEMPLATE_DIR" "$TARGET_DIR"

# ── Replace placeholders ──────────────────────────────────────────────────────
# Derive a safe identifier for variable names (hyphens → underscores)
GAME_ID_SAFE="${GAME_ID//-/_}"

find "$TARGET_DIR" -type f \( -name "*.ts" -o -name "*.json" -o -name "*.md" \) | while read -r file; do
  sed -i.bak \
    -e "s/game-template/$GAME_ID/g" \
    -e "s/game_template/$GAME_ID_SAFE/g" \
    -e "s/Game Template/$GAME_NAME/g" \
    -e "s/TemplateGame/$(echo "$GAME_NAME" | sed 's/ //g')/g" \
    "$file"
  rm "${file}.bak"
done

# ── Update package name ───────────────────────────────────────────────────────
sed -i.bak "s/@studio\/game-template/@studio\/$GAME_ID/g" "$TARGET_DIR/package.json"
rm "$TARGET_DIR/package.json.bak"

echo ""
echo "✅ Game scaffolded at: games/$GAME_ID"
echo ""
echo "Next steps:"
echo "  1. Edit games/$GAME_ID/src/bootstrap/GameBootstrap.ts"
echo "     → Update storeUrls, minimumVersions, and add game-specific services"
echo ""
echo "  2. Register in functions/src/di/functions.container.ts:"
echo "     import { ${GAME_NAME// /}Bootstrap } from '../../games/$GAME_ID/src/bootstrap/GameBootstrap';"
echo "     GameServiceFactory.register(new ${GAME_NAME// /}Bootstrap());"
echo ""
echo "  3. Add game-specific Remote Config keys in Firebase console"
echo "     Prefix all keys with: ${GAME_ID_SAFE}_"
echo ""
echo "  4. Export game functions in functions/src/index.ts:"
echo "     export * from '../../games/$GAME_ID/src/functions/game.functions';"
echo ""
echo "  5. npm install && npm run build"
