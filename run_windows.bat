@echo off
cd /d "%~dp0"
echo [1/3] Building...
flutter build windows --debug
echo [2/3] Copiando DLLs...
copy "build\windows\x64\install\*.dll" "build\windows\x64\runner\Debug\" /Y >nul
xcopy "build\windows\x64\install\data" "build\windows\x64\runner\Debug\data\" /E /Y /I /Q >nul
echo [3/3] Iniciando app...
cd build\windows\x64\runner\Debug
gestao_bar_pos.exe