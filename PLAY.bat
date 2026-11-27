@echo off
cd /d "%~dp0" || exit /b 1
start "" "%SystemRoot%\System32\wscript.exe" "%CD%\OpenGL.vbs"
