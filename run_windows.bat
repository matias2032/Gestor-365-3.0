@REM @echo off
@REM cd /d "%~dp0"

@REM echo [1/4] Building...
@REM flutter build windows --debug

@REM echo [2/4] Copiando DLLs...
@REM copy "build\windows\x64\install\*.dll" "build\windows\x64\runner\Debug\" /Y >nul
@REM xcopy "build\windows\x64\install\data" "build\windows\x64\runner\Debug\data\" /E /Y /I /Q >nul

@REM echo [3/4] Copiando SumatraPDF...
@REM copy "C:\SumatraPDF\SumatraPDF-3.5.2-64.exe" "build\windows\x64\runner\Debug\SumatraPDF.exe" /Y >nul

@REM echo [4/4] Iniciando app...
@REM cd build\windows\x64\runner\Debug
@REM gestao_bar_pos.exe


@REM Para release
@echo off
cd /d "%~dp0"

echo [1/5] Building Release...
flutter build windows --release

echo [2/5] Copiando DLLs para Release...
copy "build\windows\x64\install\*.dll" "build\windows\x64\runner\Release\" /Y >nul
xcopy "build\windows\x64\install\data" "build\windows\x64\runner\Release\data\" /E /Y /I /Q >nul

echo [3/5] Copiando SumatraPDF para Release...
copy "C:\SumatraPDF\SumatraPDF-3.5.2-64.exe" "build\windows\x64\runner\Release\SumatraPDF.exe" /Y >nul

echo [4/5] Gerando instalador...
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" instalador.iss

echo [5/5] Concluido!
echo Instalador gerado em: installer_output\Gestor365_Setup.exe
pause