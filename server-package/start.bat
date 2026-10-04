@echo off
rem ProMarket server — Windows. Double-click to start; allow access in the Windows Firewall prompt.
cd /d "%~dp0"
if exist node\node.exe (set NODE=node\node.exe) else (set NODE=node)
:run
%NODE% src\server.js
rem Exit code 42 = the server updated itself: start it again with the new version.
if %errorlevel%==42 goto run
pause
