[Setup]
AppName=Gestor 365
AppVersion=1.0.0
AppPublisher=Bar Digital
DefaultDirName={pf}\Gestor365
DefaultGroupName=Gestor 365
OutputBaseFilename=Gestor365_Setup
OutputDir=installer_output
Compression=lzma
SolidCompression=yes
SetupIconFile=windows\runner\resources\app_icon.ico

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Gestor 365"; Filename: "{app}\gestor_365.exe"
Name: "{userdesktop}\Gestor 365"; Filename: "{app}\gestor_365.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Criar atalho no Ambiente de Trabalho"; GroupDescription: "Atalhos adicionais"

[Run]
Filename: "{app}\gestor_365.exe"; Description: "Abrir Gestor 365"; Flags: nowait postinstall skipifsilent
