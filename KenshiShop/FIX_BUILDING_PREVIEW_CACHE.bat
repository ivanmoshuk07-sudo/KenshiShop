@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul 2>&1
REM Run ONLY after Kenshi game has been completely closed.
REM Move two KenshiShop build-menu generated thumbnails to a backup folder.
REM No game data, save files, and no other icons are changed.
set "GAME="
if not "%~1"=="" if exist "%~1\data" set "GAME=%~f1"
if not defined GAME for %%D in ("%~dp0..\.." "%~dp0..\..\..\..\..\common\Kenshi") do if exist "%%~fD\data" set "GAME=%%~fD"
if not defined GAME (
 echo ERROR: Kenshi game folder not found.
 echo Place this .bat in Kenshi\mods\KenshiShop, or drag the Kenshi game folder onto it.
 pause
 exit /b 1
)
echo Kenshi: %GAME%
echo Make sure Kenshi is CLOSED before continuing.
choice /C YN /M "Continue with clearing only two KenshiShop icon files"
if errorlevel 2 exit /b 0
set "BACKUP=%GAME%\KenshiShop_IconBackup_%RANDOM%"
set /a moved=0
if exist "%GAME%\data\icons\buildings\102-KenshiShop.mod.png" (
 mkdir "%BACKUP%\buildings" >nul 2>&1
 move /Y "%GAME%\data\icons\buildings\102-KenshiShop.mod.png" "%BACKUP%\buildings\102-KenshiShop.mod.png" >nul
 if not errorlevel 1 set /a moved+=1
)
if exist "%GAME%\data\icons\buildings\103-KenshiShop.mod.png" (
 mkdir "%BACKUP%\buildings" >nul 2>&1
 move /Y "%GAME%\data\icons\buildings\103-KenshiShop.mod.png" "%BACKUP%\buildings\103-KenshiShop.mod.png" >nul
 if not errorlevel 1 set /a moved+=1
)
if exist "%GAME%\data\icons\102-KenshiShop.mod.png" (
 mkdir "%BACKUP%\icons" >nul 2>&1
 move /Y "%GAME%\data\icons\102-KenshiShop.mod.png" "%BACKUP%\icons\102-KenshiShop.mod.png" >nul
 if not errorlevel 1 set /a moved+=1
)
if exist "%GAME%\data\icons\103-KenshiShop.mod.png" (
 mkdir "%BACKUP%\icons" >nul 2>&1
 move /Y "%GAME%\data\icons\103-KenshiShop.mod.png" "%BACKUP%\icons\103-KenshiShop.mod.png" >nul
 if not errorlevel 1 set /a moved+=1
)
echo Icon files moved to backup: %moved%
if %moved% EQU 0 (
 echo No cached KenshiShop thumbnails found. Icon generation might not be the source.
) else (
 echo Backup at: %BACKUP%
 echo Start Kenshi again to generate new thumbnails from the current L-House records.
)
pause
exit /b 0
