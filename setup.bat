@echo off
rem One-time setup: unpack GUT and install the tester subagent.
cd /d "%~dp0"
powershell -NoProfile -Command "Expand-Archive -Force '_setup\gut.zip' '.'"
if not exist .claude\agents mkdir .claude\agents
copy /Y _setup\tester.md .claude\agents\tester.md >nul
copy /Y _setup\designer.md .claude\agents\designer.md >nul
echo Setup done.
