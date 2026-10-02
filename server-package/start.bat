@echo off
rem ProMarket server — Windows. Double-click to start; allow access in the Windows Firewall prompt.
cd /d "%~dp0"
if exist node\node.exe (set NODE=node\node.exe) else (set NODE=node)
%NODE% src\server.js
pause
