#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
POLYGON_API_KEY="$(< /tmp/mv_polygon_key.txt)"
export POLYGON_API_KEY
.venv/bin/uvicorn server:app --host 127.0.0.1 --port 8787