# --------------------------------------------------
# PowerShell Execution Policy (safe to re-run)
# --------------------------------------------------
try {
    Set-ExecutionPolicy -ExecutionPolicy AllSigned -Scope CurrentUser -Force
    Set-ExecutionPolicy -ExecutionPolicy AllSigned -Scope Process -Force
    Write-Host "[ OK ] PowerShell execution policy configured" -ForegroundColor Green
}
catch {
    Write-Host "[WARN] Unable to set execution policy: $_" -ForegroundColor Yellow
}

# Idempotent setup for Windows. Safe to re-run.
# Note: JMETER_HOME is NOT set. JMeter is found through PATH only.
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot; Set-Location $Root
$JVer = '5.6.3'; $JMDir = 'C:\apache-jmeter-5.6.3'
$Port = if ($env:MCP_PORT) { $env:MCP_PORT } else { 8080 }
$ok = @(); $fail = @()
function Ok($m){ $script:ok += $m; Write-Host "[ OK ] $m" -ForegroundColor Green }
function Bad($m){ $script:fail += $m; Write-Host "[FAIL] $m" -ForegroundColor Red }

# 1. Python
$py = $null
foreach ($c in 'python','py') { if (Get-Command $c -ErrorAction SilentlyContinue) { $py = $c; break } }
if (-not $py) { Bad 'Python not found. Install Python 3.10+ from python.org and re-run.'; exit 1 }
Ok "Python: $(& $py --version 2>&1)"

# 2. venv (uv itself is installed from requirements.txt in step 3)
if (-not (Test-Path '.venv\Scripts\Activate.ps1')) { & $py -m venv .venv }
if (Test-Path '.venv\Scripts\Activate.ps1') { . .\.venv\Scripts\Activate.ps1; Ok "venv active: $env:VIRTUAL_ENV" } else { Bad 'venv creation failed'; exit 1 }

# 3. requirements (includes uv), with fallbacks
pip install -r requirements.txt; $done = ($LASTEXITCODE -eq 0)
if (-not $done) { & $py -m pip install -r requirements.txt; $done = ($LASTEXITCODE -eq 0) }
if ($done) { Ok 'requirements installed' } else { Bad 'pip install failed' }
if (Get-Command uv -ErrorAction SilentlyContinue) { Ok "uv: $(uv --version)" } else { Bad 'uv not available after install' }

# 4. Java
if (Get-Command java -ErrorAction SilentlyContinue) { Ok "Java: $((java -version 2>&1 | Select-Object -First 1))" } else { Bad 'Java not found. Install JDK 17+ (e.g. winget install EclipseAdoptium.Temurin.17.JDK).' }

# 5. JMeter (PATH only, no JMETER_HOME)
if (-not (Get-Command jmeter -ErrorAction SilentlyContinue)) {
  if (-not (Test-Path "$JMDir\bin\jmeter.bat")) {
    Write-Host "Downloading JMeter $JVer to $JMDir ..."
    try {
      $zip = Join-Path $env:TEMP "jmeter-$JVer.zip"
      Invoke-WebRequest "https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-$JVer.zip" -OutFile $zip
      Expand-Archive $zip -DestinationPath 'C:\' -Force; Ok "JMeter extracted to $JMDir"
    } catch { Bad "JMeter download failed: $_" }
  }
  $userPath = [Environment]::GetEnvironmentVariable('Path','User'); if (-not $userPath) { $userPath = '' }
  if ($userPath -notlike "*$JMDir\bin*") {
    # .NET API instead of setx: setx truncates PATH at 1024 characters
    [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ";$JMDir\bin"), 'User')
  }
  if ($env:Path -notlike "*$JMDir\bin*") { $env:Path += ";$JMDir\bin" }
}
$v = (jmeter -v 2>&1) -join ' '
if ($v -match 'Copyright') { Ok 'jmeter -v works' } else { Bad 'jmeter -v failed (is Java installed?)' }

# 6. MCP server
function Health { try { (Invoke-WebRequest "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 3).Content } catch { $null } }
if (-not (Health)) {
  New-Item -ItemType Directory -Force .logs | Out-Null
  Start-Process -FilePath ".\.venv\Scripts\python.exe" -ArgumentList 'mcp\jmeter_mcp_server.py' -WindowStyle Hidden `
    -RedirectStandardOutput .logs\mcp.log -RedirectStandardError .logs\mcp.err
  1..20 | ForEach-Object { Start-Sleep 1; if (Health) { return } }
}
$h = Health
if ($h) { Ok "MCP URL: http://localhost:$Port/mcp | health: $h" } else { Bad 'MCP server not healthy (see .logs\mcp.err)' }

# 7. Summary
Write-Host "`n=== Summary ==="; $ok | ForEach-Object { Write-Host " + $_" -ForegroundColor Green }; $fail | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
Write-Host 'Open a NEW terminal so PATH changes apply. For remote use set MCP_HOST=0.0.0.0 first.'
if ($fail.Count -gt 0) { exit 1 }
