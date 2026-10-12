@echo off
rem CareFlow live app on phone. Double-click, or run from a terminal. See tasks.py for details.
title CareFlow live app on phone
cd /d "%~dp0"
python tasks.py phone-live %*
echo.
pause
