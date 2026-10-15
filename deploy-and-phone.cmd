@echo off
rem CareFlow: deploy everything to the LIVE project, then install the live app on the phone.
rem Double-click, or run from a terminal. Plug the phone in first. See tasks.py.
rem Extra arguments (e.g. --yes) go to deploy-all; phone-live runs only if the deploy succeeds.
title CareFlow deploy + phone
cd /d "%~dp0"
python tasks.py deploy-all %*
if errorlevel 1 (
  echo.
  echo Deploy failed, so the phone app was not installed.
  pause
  exit /b 1
)
echo.
echo Deploy done. Installing the live app on the phone...
python tasks.py phone-live
echo.
pause
