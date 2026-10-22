# Aasure: End-to-End Performance Testing for VS Code Agent Mode

Markdown agents for performance NFR creation, Postman/HAR/JMX analysis and scripting, approved smoke/load execution, read-only Dynatrace MCP monitoring, and evidence-based RCA reporting. Offline drafting does not authorize test execution.

## Prerequisites
- VS Code with GitHub Copilot Chat (Agent mode, custom agents enabled)
- Python 3.10+ and Java JDK 17+
- Internet access for first-time setup (JMeter 5.6.3 is downloaded if `jmeter` is not already on PATH)

`JMETER_HOME` is **not** used anywhere. JMeter is found through `PATH` only.

---

## How to run the solution (step by step)

### 1. Get the project
Clone or unzip it and open the project root folder in VS Code (the folder that contains `agents/`).

This checkout stores eight agent definitions in `agents/`. VS Code's default workspace discovery location is `.github/agents/`; use your team's configured agent location or publish all eight definitions there before invoking Aasure. The orchestrator and its seven specialists must all be discoverable. Agent definitions inherit the selected runtime model rather than pinning a model name.

### 2. Run the startup script
| OS | Command (from the project root) |
|---|---|
| Windows | `startup\start.bat` |
| Linux / macOS | `bash startup/start.sh` |

The script, in order: checks Python, creates `.venv`, installs `requirements.txt` (including `uv`), verifies Java, finds or installs JMeter 5.6.3 and puts its `bin` folder on PATH, starts the MCP server, and prints a summary. It is safe to re-run.

JMeter install locations when it is not already present: `C:\apache-jmeter-5.6.3` (Windows) or `~/apache-jmeter-5.6.3` (Linux/macOS).

### 3. Verify in a NEW terminal
```
jmeter -v
curl http://localhost:8765/health        # Windows PowerShell: Invoke-WebRequest http://localhost:8765/health
```
`jmeter -v` must print the version banner, and `/health` must return `"status": "ok"`.

### 4. Register the MCP server in VS Code
Create `.vscode/mcp.json` (template: `mcp/mcp.json.example`):
```json
{
	"servers": {
		"jmeter-mcp": {
			"type": "http",
			"url": "http://localhost:8080/mcp"
		},
		"dynatrace-mcp": {
			"type": "http",
			"url": "<your-approved-dynatrace-mcp-endpoint>"
		}
	}
}
```
Replace `<your-approved-dynatrace-mcp-endpoint>` with the exact MCP endpoint provided by your Dynatrace administrator or integration owner; it must be the MCP server URL, not just the tenant URL. Keep the registered name `dynatrace-mcp` to match `agents/dynatrace-monitor.agent.md`. Configure the approved authentication method through the MCP integration's secure setup; do not put API tokens in this file or chat. Start the servers from the MCP view or the Command Palette (`MCP: List Servers`).

### 5. Put your input in `Inputs/`
Drop a Postman collection (plus environment), a HAR file, or a recorded JMX there. To try the solution first, copy the files from `samplefiles/`.

### 6. Call @Aasure
Open Copilot Chat, switch to **Agent** mode, pick **Aasure** and ask. Aasure extracts provided paths and scope, asks only for missing stage inputs, bootstraps one run folder, and delegates to the appropriate specialists. Script-only, NFR-only, connection-only, and report-only requests never start tests. Smoke and load require explicit, scoped approval; load also requires an approved NFR/profile, matching passing smoke, and enforceable stop limits.

### 7. Read the results
Everything lands in `Results/<App>_<yyyyMMdd_HHmmss>/`:
`Initial analysis.md`, `jmeter/api-test-plan.jmx`, `docs/run-manifest.json`, stage handoff packets, and stage-specific reports. NFRs use `docs/nfr.md` and `docs/nfr.json`; smoke/load evidence uses unique `results/smoke/attempt-NN/` and `results/load/attempt-NN/` folders. Telemetry goes under `monitoring/`; RCA uses `rca/rca-report.md` and `rca/metrics.json`. Only requested stages produce artifacts; earlier run folders retain their original layout.

## NFR Creation and Dynatrace Monitoring
- `performance-nfr` derives measurable requirements and workload profiles from supplied evidence. Unknown draft values remain unresolved, not invented thresholds. Requirement approval and execution approval are separate gates.
- `dynatrace-monitor` verifies an already registered MCP server with a minimal authorized read, then captures bounded baseline/snapshot/post-run evidence. No Dynatrace server implementation or tenant credentials are bundled here; configure an approved external Dynatrace MCP integration separately.
- The monitoring agent's tool pattern is `dynatrace-mcp/*`. The registered server name and granted agent tools must match. A different name requires corresponding approved tool access. Configuration alone is not proof of connectivity.
- Provide the tenant/environment reference, read-only scope, entity/service selector, UTC or approved relative window, and query limits. Configure credentials outside chat; provide only secret references. No alert muting, configuration writes, remediation, or unrestricted log exports are allowed.
- The bundled JMeter MCP `run_jmeter` is blocking and has no job-status/cancel tool or process timeout. Continuous monitoring and live stopping require a verified compatible backend or independent authorized safety observer. Otherwise the workflow blocks when these controls are required; before/after snapshots are not described as continuous monitoring.

Example requests:
```text
Create draft checkout NFRs from Inputs/checkout-requirements.md; peak traffic is unknown.
Generate JMX from samplefiles/sample.postman_collection.json using samplefiles/sample.postman_environment.json; do not execute.
Check dynatrace-mcp for my approved tenant, read-only, last 15 minutes; no load.
Analyze an existing run's JTL, approved NFR, and monitoring evidence; do not rerun.
```

The full routing, input, approval, bootstrap, and handoff contracts are in `agents/Aasure.agent.md`.

---

## Try it with the sample files
`samplefiles/` targets the public JSONPlaceholder demo API (no auth, 4 endpoints, one dependency: `userId` from *Get Post* feeds *Get User*).

| File | Use |
|---|---|
| `sample.postman_collection.json` | Postman collection (4 requests, tests, one extracted variable) |
| `sample.postman_environment.json` | Postman environment (`baseUrl`) |
| `sample.har` | HAR with 4 API calls plus noise (analytics, CSS, favicon, HTML) to test filtering |
| `sample-api-test-plan.jmx` | Reference JMX in the format the agents are expected to produce |

Example prompts:
- `Analyze samplefiles/sample.postman_collection.json only. App name: SampleApi, env: public demo, base URL https://jsonplaceholder.typicode.com`
- `Generate the JMX and run a smoke test from samplefiles/sample.postman_collection.json using samplefiles/sample.postman_environment.json`
- `Draft a full-pipeline plan from samplefiles/sample-api-test-plan.har; do not execute` (public-demo inputs are not authorization to load a shared service; use an authorized test environment for execution)

Run the reference JMX by hand (smoke):
```
jmeter -n -t samplefiles/sample-api-test-plan.jmx -l sample-results.jtl -e -o sample-report -Jusers=1 -Jloops=1
```
Delete `sample-report/` before re-running (JMeter requires an empty or missing report folder).

---

## Local JMeter configuration (manual, if you skip the script)
1. Install Java 17+ and confirm `java -version`.
2. Download `apache-jmeter-5.6.3.zip` from `https://archive.apache.org/dist/jmeter/binaries/` and extract it (e.g. `C:\apache-jmeter-5.6.3`).
3. Add the `bin` folder (`C:\apache-jmeter-5.6.3\bin`) to your user PATH. Use System Properties, not `setx`, because `setx` truncates PATH at 1024 characters.
4. Open a new terminal and run `jmeter -v`.

If you previously set `JMETER_HOME`, it is no longer needed. You can remove it (Windows: System Properties > Environment Variables; Linux/macOS: delete the export line from `~/.bashrc` or `~/.zshrc`).

## Remote MCP server
On the load machine, run the startup script, then restart the server bound to all interfaces:
```
MCP_HOST=0.0.0.0 MCP_ALLOWED_ROOT=/path/to/repo python mcp/jmeter_mcp_server.py
```
Point `url` in `mcp.json` at `http://<host>:8765/mcp`. The server has **no authentication** by default: keep it behind a VPN or firewall. Limits: `MAX_USERS` (default 50), and all paths are confined to `MCP_ALLOWED_ROOT`.

## Distributed execution
1. Same JMeter and JDK version on the controller and every slave; same CSV files at the same paths.
2. On each slave: `jmeter-server -Djava.rmi.server.hostname=<slave-ip>`.
3. Properties: `server_port=1099`, `server.rmi.localport=4000`. For a lab, `server.rmi.ssl.disable=true`; otherwise create keystores with `create-rmi-keystore` and distribute `rmi_keystore.jks`.
4. Open ports 1099, 4000 and (controller) 4001 between controller and slaves.
5. Run with `-R slave1,slave2`. `jmeter-loadexec` performs the pre-flight check and writes `docs/preflight.md`.

## Folder structure
```
agents/           Aasure + 7 specialists (publish/register for VS Code discovery)
startup/          start.ps1  start.bat  start.sh
mcp/              jmeter_mcp_server.py  mcp.json.example
samplefiles/      sample Postman, HAR and JMX
Inputs/           your input files
Results/<App>_<yyyyMMdd_HHmmss>/
requirements.txt  (uv, mcp, pandas, uvicorn)
```

## Troubleshooting
- `jmeter` not found: open a **new** terminal (PATH changes apply only to new sessions) and check `where jmeter` / `which jmeter`.
- "folder not empty" report error: use a new attempt directory; agents preserve existing JTL/report evidence instead of deleting it.
- MCP unhealthy: read `.logs/mcp.log` and `.logs/mcp.err`; confirm Java is installed and port 8765 is free.
- Agents not visible: confirm all eight definitions are registered for discovery (default `.github/agents/`). This checkout keeps source definitions in `agents/`; no model pin is required.
- Dynatrace tools unavailable: verify external MCP registration, matching server/tool-access name, tenant, and read-only permissions. Never paste API tokens into chat or bypass MCP with direct HTTP calls.
- `pip install` fails: the scripts retry with `python -m pip`; check proxy/network settings.
- Slaves not found: check RMI ports, `java.rmi.server.hostname`, and firewall.

## Security notes
- Never put real secrets in chat, `Inputs/`, or JMX. Use `${__P(...)}` or `${__env(...)}`.
- Agents write only inside the run folder. Load tests never target production without written confirmation.
- Secure or isolate the MCP server on any shared network.
