@echo off
rem WhatEat release - one click: bump version, sync code, push, wait CI, download APK
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0release.ps1" %*
if errorlevel 1 (
  echo.
  echo [release FAILED] - read the message above.
  pause
)
