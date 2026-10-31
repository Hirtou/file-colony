@echo off
rem GUT tests, no window. Output also saved to logs\tests.txt
cd /d "%~dp0"
if not exist addons\gut\gut_cmdln.gd call setup.bat
if not exist logs mkdir logs
set GODOT=C:\Godot\godot_console.exe
"%GODOT%" --headless --path . --import > logs\import.txt 2>&1
"%GODOT%" --headless --path . -s addons/gut/gut_cmdln.gd > logs\tests.txt 2>&1
type logs\tests.txt
