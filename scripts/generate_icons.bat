@echo off
echo Flutter Icon Generator
echo ======================
echo.

REM Navigate to scripts directory
cd /d "%~dp0"

REM Check if node_modules exists
if not exist "node_modules" (
    echo Installing dependencies...
    npm install
    echo.
)

REM Run the icon generator
echo Generating icons from SVG...
node generate_icons.js

echo.
echo Press any key to exit...
pause > nul 