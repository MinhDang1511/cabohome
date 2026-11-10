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
git push

echo.
echo Done. GitHub Pages will update in a minute or two at:
echo https://minhdang1511.github.io/cabohome/
echo.
pause
