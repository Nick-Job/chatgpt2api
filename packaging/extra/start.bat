@echo off
chcp 65001 >nul
cd /d "%~dp0"
title ChatGPT2API
ChatGPT2API.exe
if errorlevel 1 pause
