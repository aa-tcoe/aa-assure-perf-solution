#!/usr/bin/env bash
# Idempotent setup for Linux/macOS. Safe to re-run.
# Note: JMETER_HOME is NOT set. JMeter is found through PATH only.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
JMETER_VER="5.6.3"; JM_DIR="$HOME/apache-jmeter-$JMETER_VER"
PORT="${MCP_PORT:-8765}"; OK=(); FAIL=()
ok(){ OK+=("$1"); echo "[ OK ] $1"; }; bad(){ FAIL+=("$1"); echo "[FAIL] $1" >&2; }

# 1. Python
PY=$(command -v python3 || command -v python || true)
if [ -z "$PY" ]; then bad "Python not found. Install Python 3.10+ and re-run."; exit 1; fi
ok "Python: $($PY --version 2>&1)"

# 2. venv (uv itself is installed from requirements.txt in step 3)
if [ ! -d .venv ]; then "$PY" -m venv .venv || { bad "venv creation failed"; exit 1; }; fi
# shellcheck disable=SC1091
source .venv/bin/activate && ok "venv active: $VIRTUAL_ENV"

# 3. requirements (includes uv), with fallbacks
if pip install -r requirements.txt || python -m pip install -r requirements.txt; then ok "requirements installed"; else bad "pip install failed"; fi
command -v uv >/dev/null 2>&1 && ok "uv: $(uv --version)" || bad "uv not available after install"

# 4. Java
if command -v java >/dev/null 2>&1; then ok "Java: $(java -version 2>&1 | head -1)"; else bad "Java not found. Install JDK 17+ (e.g. 'brew install openjdk' or 'sudo apt install openjdk-17-jre')."; fi

# 5. JMeter (PATH only, no JMETER_HOME)
if ! command -v jmeter >/dev/null 2>&1; then
  if [ ! -x "$JM_DIR/bin/jmeter" ]; then
    echo "Downloading JMeter $JMETER_VER to $JM_DIR ..."
    T=$(mktemp -d); URL="https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-$JMETER_VER.tgz"
    if curl -fL "$URL" -o "$T/j.tgz" && tar -xzf "$T/j.tgz" -C "$HOME"; then ok "JMeter extracted to $JM_DIR"; else bad "JMeter download failed ($URL)"; fi
  fi
  export PATH="$JM_DIR/bin:$PATH"
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] && ! grep -q "apache-jmeter-$JMETER_VER/bin" "$rc" && printf '\nexport PATH="%s/bin:$PATH"\n' "$JM_DIR" >> "$rc"
  done
fi
if jmeter -v 2>&1 | grep -q "Copyright"; then ok "jmeter -v works ($(command -v jmeter))"; else bad "jmeter -v failed"; fi

# 6. MCP server
if curl -fs "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then ok "MCP server already running"
else
  mkdir -p .logs; nohup python mcp/jmeter_mcp_server.py > .logs/mcp.log 2>&1 & echo $! > .logs/mcp.pid
  for _ in $(seq 1 20); do sleep 1; curl -fs "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break; done
fi
H=$(curl -fs "http://127.0.0.1:$PORT/health" 2>/dev/null || true)
if [ -n "$H" ]; then ok "MCP URL: http://localhost:$PORT/mcp | health: $H"; else bad "MCP server not healthy (see .logs/mcp.log)"; fi

# 7. Summary
echo; echo "=== Summary ==="; printf ' + %s\n' "${OK[@]}"; [ ${#FAIL[@]} -gt 0 ] && printf ' - %s\n' "${FAIL[@]}"
echo "Open a NEW terminal for PATH changes. Remote MCP: set MCP_HOST=0.0.0.0 before running."
[ ${#FAIL[@]} -eq 0 ]
