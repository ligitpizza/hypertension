@echo off
rem CareFlow: deploy rules, backend, staff portal and scheduler jobs to the LIVE project.
rem Double-click, or run from a terminal. Asks once before deploying. See tasks.py.
title CareFlow deploy to cloud
cd /d "%~dp0"
python tasks.py deploy-all %*
echo.
pause
