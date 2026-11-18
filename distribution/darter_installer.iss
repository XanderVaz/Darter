; Instalador de Darter para Windows (Inno Setup 6).
; Se instala en la carpeta del usuario (sin pedir administrador), así el actualizador
; automático puede reemplazar los archivos sin permisos especiales.
; AJUSTA: AppPublisher y el nombre del .exe (el nombre del proyecto de Flutter, p. ej. darter.exe).

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#define AppName "Darter"
#define AppExe "darter.exe"

[Setup]
AppId={{654FF541-F521-4498-9E46-18EC49CDE8A0}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=TU NOMBRE
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Darter-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear un icono en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Abrir {#AppName}"; Flags: nowait postinstall skipifsilent
