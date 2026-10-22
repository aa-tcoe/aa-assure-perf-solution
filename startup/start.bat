@echo off
REM Wrapper: runs start.ps1 with a process-scoped execution policy bypass.
REM JMETER_HOME is intentionally not set. start.ps1 puts JMeter bin on the user PATH.
where powershell >nul 2>&1 || (echo [FAIL] PowerShell not found & exit /b 1)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1"
exit /b %ERRORLEVEL%
