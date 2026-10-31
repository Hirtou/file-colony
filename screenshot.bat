@echo off
rem Runs the scene and saves screenshots\latest.png. Output in logs\screenshot.txt
cd /d "%~dp0"
if not exist logs mkdir logs
set GODOT=C:\Godot\godot_console.exe
"%GODOT%" --headless --path . --import > logs\import.txt 2>&1
"%GODOT%" --path . -s tools/screenshot.gd -- %* >logs\screenshot.txt 2>&1
type logs\screenshot.txt
