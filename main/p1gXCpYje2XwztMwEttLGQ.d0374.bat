@echo off
cd /d "%~dp0"

echo ============================================
echo   Pushing CABO build to GitHub Pages
echo ============================================
echo.

git add -A

set /p msg=Commit message (press Enter for default "Update build"): 
if "%msg%"=="" set msg=Update build

git commit -m "%msg%"
if errorlevel 1 (
    echo.
    echo Nothing to commit - build folder matches what's already pushed.
    pause
    exit /b 0
)

echo.
echo Pushing to GitHub...
git push -u origin main

if errorlevel 1 (
    echo.
    echo ============================================
    echo   PUSH FAILED - see the error above.
    echo   Nothing went live. Copy this window's text
    echo   and send it over so it can be diagnosed.
    echo ============================================
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================
echo   SUCCESS - pushed to GitHub.
echo   GitHub Pages will update in a minute or two at:
echo   https://minhdang1511.github.io/cabohome/
echo ============================================
echo.
pause
