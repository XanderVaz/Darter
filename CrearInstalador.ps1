Add-Type -AssemblyName System.Windows.Forms

# 1. Buscar el compilador de Inno Setup
$isccPath = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $isccPath)) {
    $isccPath = "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
}

if (-not (Test-Path $isccPath)) {
    [System.Windows.Forms.MessageBox]::Show("No se encontró Inno Setup 6. Por favor instálalo antes de continuar.", "Error", 0, 16)
    exit
}

# 2. Seleccionar el archivo .exe principal
$fileDialog = New-Object System.Windows.Forms.OpenFileDialog
$fileDialog.Title = "Selecciona el archivo .EXE principal de tu app Flutter"
$fileDialog.Filter = "Archivos Ejecutables (*.exe)|*.exe"

if ($fileDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    exit
}
$exeFullPath = $fileDialog.FileName
$exeName = [System.IO.Path]::GetFileName($exeFullPath)
$appName = [System.IO.Path]::GetFileNameWithoutExtension($exeFullPath)

# 3. Seleccionar la carpeta de compilación (ej. Release)
$folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$folderDialog.Description = "Selecciona la carpeta completa de tu aplicación (ej. build\windows\x64\runner\Release)"
$folderDialog.SelectedPath = [System.IO.Path]::GetDirectoryName($exeFullPath)

if ($folderDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    exit
}
$releaseFolder = $folderDialog.SelectedPath

# 4. Definir dónde se guardará el instalador final (Escritorio)
$outputDir = [Environment]::GetFolderPath("Desktop")
$setupName = "Instalador_$appName"
$guid = [guid]::NewGuid().ToString().ToUpper()

# 5. Generar el archivo temporal .iss de Inno Setup
$issContent = @"
[Setup]
AppId={{$guid}
AppName=$appName
AppVersion=1.0.0
DefaultDirName={autopf}\$appName
DefaultGroupName=$appName
OutputDir=$outputDir
OutputBaseFilename=$setupName
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "$exeFullPath"; DestDir: "{app}"; Flags: ignoreversion
Source: "$releaseFolder\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\$appName"; Filename: "{app}\$exeName"
Name: "{autodesktop}\$appName"; Filename: "{app}\$exeName"; Tasks: desktopicon

[Run]
Filename: "{app}\$exeName"; Description: "{cm:LaunchProgram,{#StringChange('$appName', '&', '&&')}}"; Flags: nowait postinstall skipifsilent
"@

$tempIssPath = "$env:TEMP\setup_flutter_temp.iss"
$issContent | Out-File -FilePath $tempIssPath -Encoding UTF8

# 6. Ejecutar Inno Setup para compilar el instalador
Write-Host "Compilando instalador, por favor espera..." -ForegroundColor Cyan
& $isccPath $tempIssPath

# 7. Limpiar y avisar
Remove-Item $tempIssPath -ErrorAction SilentlyContinue
[System.Windows.Forms.MessageBox]::Show("¡Instalador creado con éxito en tu Escritorio!`nArchivo: $setupName.exe", "Proceso Completado", 0, 64)
