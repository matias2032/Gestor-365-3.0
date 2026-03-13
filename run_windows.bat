@REM @echo off
@REM cd /d "%~dp0"
@REM echo [1/3] Building...
@REM flutter build windows --debug
@REM echo [2/3] Copiando DLLs...
@REM copy "build\windows\x64\install\*.dll" "build\windows\x64\runner\Debug\" /Y >nul
@REM xcopy "build\windows\x64\install\data" "build\windows\x64\runner\Debug\data\" /E /Y /I /Q >nul
@REM echo [3/3] Iniciando app...
@REM cd build\windows\x64\runner\Debug
@REM gestao_bar_pos.exe


@echo off
cd /d "%~dp0"

echo [1/4] Building...
flutter build windows --debug

echo [2/4] Copiando DLLs...
copy "build\windows\x64\install\*.dll" "build\windows\x64\runner\Debug\" /Y >nul
xcopy "build\windows\x64\install\data" "build\windows\x64\runner\Debug\data\" /E /Y /I /Q >nul

echo [3/4] Copiando SumatraPDF...
copy "C:\SumatraPDF\SumatraPDF-3.5.2-64.exe" "build\windows\x64\runner\Debug\SumatraPDF.exe" /Y >nul

echo [4/4] Iniciando app...
cd build\windows\x64\runner\Debug
gestao_bar_pos.exe