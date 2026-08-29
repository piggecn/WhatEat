@echo off
rem WhatEat backend release: create + push version tag, GitHub then builds Docker image and publishes Release
rem Usage: release-tag.bat [version]   (empty = patch +1)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0release-tag.ps1" %*
if errorlevel 1 (
  echo.
  echo [release-tag FAILED] - read the message above.
  pause
)
