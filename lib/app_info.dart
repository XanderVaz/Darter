/// ───────────────────────────────────────────────────────────────
///  INFORMACIÓN DE LA APP — EDITA ESTE ARCHIVO ANTES DE DISTRIBUIR
/// ───────────────────────────────────────────────────────────────

/// Versión que muestra «Acerca de» y que compara el actualizador.
/// Se puede fijar al compilar:  flutter build windows --dart-define=APP_VERSION=1.2.0
const kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.12');
const kBuildNumber = String.fromEnvironment('APP_BUILD', defaultValue: '1');

// ── Creador (aparece en «Acerca de») ──
const kCreatorName = 'Xander Vaz'; // ← cámbialo
const kCreatorRole = 'Creador y desarrollador';
const kCreatorEmail = 'darterapp@gmail.com'; // opcional: correo de contacto
const kCreatorWebsite = 'https://xndrdevs.xyz/'; // opcional: https://tusitio.com
const kCreatorGithub = 'XanderVaz'; // opcional: tu usuario de GitHub (sin @)

// ── Repositorio de GitHub (actualizaciones, notas y reportes) ──
const kGithubOwner = 'XanderVaz'; // ← usuario u organización dueña del repo
const kGithubRepo = 'Darter'; // ← nombre del repositorio
const kRepoConfigured = kGithubOwner != 'TU_USUARIO';

// ── Firma digital ──
/// Parte del «Subject» de tu certificado de firma (p. ej. 'CN=Tu Nombre').
/// Si no está vacío, el actualizador RECHAZA cualquier actualización cuya firma no sea válida
/// o no sea de este editor. Déjalo '' mientras no firmes tus versiones. Ver distribution/signing/SIGNING.md
const kExpectedSigner = '';

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
