@echo off
rem CareFlow local development. Double-click, or run from a terminal. See tasks.py for details.
title CareFlow local development
cd /d "%~dp0"
python tasks.py dev %*
echo.
pause
