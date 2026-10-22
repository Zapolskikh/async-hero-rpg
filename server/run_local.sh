#!/usr/bin/env bash
# Run the server locally without Docker (SQLite by default).
#   ./run_local.sh                 -> http://127.0.0.1:8000
#   DATABASE_URL=postgresql+asyncpg://user:pass@host/db ./run_local.sh
set -euo pipefail
cd "$(dirname "$0")"
export GODOT_BIN="${GODOT_BIN:-godot}"
export PROJECT_DIR="${PROJECT_DIR:-$(cd .. && pwd)}"
export DATABASE_URL="${DATABASE_URL:-sqlite+aiosqlite:///./hero.db}"
if [ ! -f "$PROJECT_DIR/.godot/global_script_class_cache.cfg" ]; then
  "$GODOT_BIN" --headless --import --path "$PROJECT_DIR" >/dev/null 2>&1 || true
fi
exec python3 -m uvicorn app.main:app --host "${HOST:-127.0.0.1}" --port "${PORT:-8000}"
