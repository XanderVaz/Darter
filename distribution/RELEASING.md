# Cómo publicar una versión de Darter (GitHub Releases)

## 1. Configura la app (una sola vez)
Edita `lib/app_info.dart`:
- `kCreatorName`, `kCreatorRole` y tus enlaces (correo, web, GitHub) → aparecen en **Acerca de**.
- `kGithubOwner` y `kGithubRepo` → de aquí sale el actualizador y el botón "Reportar un problema".
- `kLicenseName` y `kCopyrightYear`.

En `distribution/darter_installer.iss` cambia `AppPublisher` y, si tu proyecto no se llama `darter`, el nombre del `.exe`.

## 2. Sube el proyecto a GitHub (repositorio público)
Copia a la raíz de tu proyecto:
- `.github/workflows/release.yml`
- `distribution/darter_installer.iss`

> El actualizador lee la API pública de GitHub, así que las releases deben estar en un repositorio **público**.

## 3. Publicar una versión (automático)
```
git tag v1.0.1
git push origin v1.0.1
```
GitHub Actions compila Windows, crea y sube a la release:
- `Darter-1.0.1-windows-x64.zip`  → lo usa el actualizador (reemplaza archivos y reinicia solo)
- `Darter-1.0.1-windows-x64-setup.exe` → instalador para usuarios nuevos

Las notas de la versión se generan de los commits; puedes editarlas en GitHub (se muestran dentro de la app).

**Betas:** usa una etiqueta con guion (`v1.1.0-beta.1`): se marca como pre-lanzamiento y solo la ven quienes activen "Recibir versiones beta".

## 4. Publicar a mano (sin Actions)
```
flutter build windows --release --dart-define=APP_VERSION=1.0.1
```
Comprime el **contenido** de `build\windows\x64\runner\Release\` en `Darter-1.0.1-windows-x64.zip`
(el .exe debe quedar en la raíz del .zip, junto a `flutter_windows.dll`) y súbelo a
GitHub → Releases → *Draft a new release* con la etiqueta `v1.0.1`.

## 5. Reglas que usa el actualizador
- La etiqueta debe ser `vX.Y.Z` (o `vX.Y.Z-beta.N`). Se compara con `kAppVersion` (que se fija con `--dart-define=APP_VERSION`).
- El nombre del archivo debe contener `windows` (`macos` / `linux` en otros sistemas). Si hay `.zip` y `.exe`, usa el `.zip`.
- Integridad: GitHub calcula el SHA-256 de cada archivo; Darter lo verifica antes de instalar. Si no coincide, **no instala nada**.
- Se busca al iniciar (máx. una vez al día, se puede desactivar) y con **Ayuda → Buscar actualizaciones**.

## 6. Probar el actualizador
1. Compila con `--dart-define=APP_VERSION=0.9.0` e instala esa versión.
2. Publica la release `v1.0.0` en GitHub.
3. Abre la app → **Ayuda → Buscar actualizaciones** → *Descargar e instalar*.

## 7. Antes de distribuir en serio
- Windows SmartScreen avisará de "editor desconocido" hasta que firmes el `.exe` con un certificado de firma de código.
- Mantén `version:` de `pubspec.yaml` igual a la versión publicada (la usa el recurso de versión del `.exe`).
- Decide tu licencia (`kLicenseName`) y añade un archivo `LICENSE` al repositorio.
