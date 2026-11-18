# Dart IDE (Flutter Desktop)

1. `flutter create --platforms=windows,macos,linux .`   (en esta carpeta; no pisa lib/ ni pubspec.yaml)
2. `flutter pub get`
3. `flutter run -d windows` (o macos / linux)

Requisitos: Flutter SDK en el PATH. Monaco se carga desde CDN (necesita internet).
Nota: flutter_inappwebview soporta Windows y macOS; en Linux el editor WebView no está soportado oficialmente.
