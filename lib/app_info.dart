/// ───────────────────────────────────────────────────────────────
///  INFORMACIÓN DE LA APP — EDITA ESTE ARCHIVO ANTES DE DISTRIBUIR
/// ───────────────────────────────────────────────────────────────

/// Versión que muestra «Acerca de» y que compara el actualizador.
/// Se puede fijar al compilar:  flutter build windows --dart-define=APP_VERSION=1.2.0
const kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
const kBuildNumber = String.fromEnvironment('APP_BUILD', defaultValue: '1');

// ── Creador (aparece en «Acerca de») ──
const kCreatorName = 'TU NOMBRE'; // ← cámbialo
const kCreatorRole = 'Creador y desarrollador';
const kCreatorEmail = ''; // opcional: correo de contacto
const kCreatorWebsite = ''; // opcional: https://tusitio.com
const kCreatorGithub = ''; // opcional: tu usuario de GitHub (sin @)

// ── Repositorio de GitHub (actualizaciones, notas y reportes) ──
const kGithubOwner = 'TU_USUARIO'; // ← usuario u organización dueña del repo
const kGithubRepo = 'darter'; // ← nombre del repositorio
const kRepoConfigured = kGithubOwner != 'TU_USUARIO';

// ── Legal ──
const kCopyrightYear = '2026';
const kLicenseName = 'Todos los derechos reservados';
const kAppDescription =
    'Un IDE moderno y ligero hecho solo para Dart y Flutter: editor Monaco, depurador, pruebas, Git, localización y mucho más.';

String get kRepoUrl => 'https://github.com/$kGithubOwner/$kGithubRepo';

String issueUrl({String? body}) {
  final b = body == null ? '' : '?body=${Uri.encodeQueryComponent(body)}';
  return '$kRepoUrl/issues/new$b';
}
