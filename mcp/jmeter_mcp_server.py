"""JMeter MCP server (streamable HTTP). Exposes JMeter run/results tools to VS Code agents.
Security: runs only .jmx files under ALLOWED_ROOT, never shells out with user-built strings."""
import os, shutil, subprocess, sys
from pathlib import Path
from mcp.server.fastmcp import FastMCP
from starlette.requests import Request
from starlette.responses import JSONResponse

HOST = os.environ.get("MCP_HOST", "127.0.0.1")   # set 0.0.0.0 only for remote use behind a firewall
PORT = int(os.environ.get("MCP_PORT", "8080"))
ALLOWED_ROOT = Path(os.environ.get("MCP_ALLOWED_ROOT", Path(__file__).resolve().parent.parent)).resolve()
MAX_USERS = int(os.environ.get("MAX_USERS", "50"))

mcp = FastMCP("jmeter-mcp", host=HOST, port=PORT)

def _jmeter() -> str:
    found = shutil.which("jmeter")  # JMeter is located through PATH only (no JMETER_HOME)
    if not found:
        raise RuntimeError("jmeter not found on PATH. Run the startup script and open a new terminal.")
    return found

def _safe(p: str) -> Path:
    path = (ALLOWED_ROOT / p).resolve() if not os.path.isabs(p) else Path(p).resolve()
    if ALLOWED_ROOT not in path.parents and path != ALLOWED_ROOT:
        raise ValueError(f"Path outside allowed root: {path}")
    return path

@mcp.custom_route("/health", methods=["GET"])
async def health(_: Request) -> JSONResponse:
    try:
        ok, ver = True, subprocess.run([_jmeter(), "-v"], capture_output=True, text=True, timeout=60).stdout[-200:]
    except Exception as e:
        ok, ver = False, str(e)
    return JSONResponse({"status": "ok" if ok else "degraded", "jmeter": ver.strip(), "root": str(ALLOWED_ROOT)})

@mcp.tool()
def jmeter_version() -> str:
    """Return the JMeter version banner."""
    r = subprocess.run([_jmeter(), "-v"], capture_output=True, text=True, timeout=60)
    return (r.stdout + r.stderr)[-1000:]

@mcp.tool()
def run_jmeter(jmx: str, jtl: str, report_dir: str = "", users: int = 1, loops: int = 1,
               duration: int = 0, think: int = 1000, dev: int = 500, remote_hosts: str = "") -> dict:
    """Run a JMX in non-GUI mode. Paths must be inside the allowed root. remote_hosts = 'h1,h2' for distributed."""
    if users > MAX_USERS:
        return {"error": f"users={users} exceeds MAX_USERS={MAX_USERS}; raise only with approval."}
    jmx_p, jtl_p = _safe(jmx), _safe(jtl)
    cmd = [_jmeter(), "-n", "-t", str(jmx_p), "-l", str(jtl_p),
           f"-Jusers={users}", f"-Jloops={loops}", f"-Jthink={think}", f"-Jdev={dev}"]
    if duration: cmd.append(f"-Jduration={duration}")
    if report_dir:
        rep = _safe(report_dir)
        if rep.exists(): shutil.rmtree(rep)   # JMeter needs an empty/nonexistent folder
        cmd += ["-e", "-o", str(rep)]
    if remote_hosts: cmd += ["-R", remote_hosts]
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=jmx_p.parent.parent)
    return {"returncode": r.returncode, "stdout_tail": r.stdout[-2000:], "stderr_tail": r.stderr[-1000:]}

@mcp.tool()
def jtl_summary(jtl: str) -> dict:
    """Per-label sample count, errors, avg/min/max and p90/p95/p99 from a CSV JTL."""
    import pandas as pd
    df = pd.read_csv(_safe(jtl))
    df["ok"] = df["success"].astype(str).str.lower() == "true"
    g = df.groupby("label")
    out = g.agg(samples=("elapsed", "count"), errors=("ok", lambda s: int((~s).sum())),
                avg=("elapsed", "mean"), min=("elapsed", "min"), max=("elapsed", "max"),
                p90=("elapsed", lambda s: s.quantile(.90)), p95=("elapsed", lambda s: s.quantile(.95)),
                p99=("elapsed", lambda s: s.quantile(.99))).round(1)
    return out.reset_index().to_dict(orient="records")

if __name__ == "__main__":
    print(f"jmeter-mcp listening on http://{HOST}:{PORT}/mcp  (health: /health)", flush=True)
    mcp.run(transport="streamable-http")
