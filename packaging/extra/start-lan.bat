@echo off
chcp 65001 >nul
cd /d "%~dp0"
title ChatGPT2API (LAN)
echo 局域网模式：同一网络内的其他设备可通过 http://本机IP:3000 访问
echo 首次运行 Windows 可能弹出防火墙提示，请选择"允许访问"。
echo.
ChatGPT2API.exe --host 0.0.0.0
if errorlevel 1 pause
