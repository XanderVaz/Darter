import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Nombre visible de la app (cámbialo aquí y se actualiza en toda la interfaz).
const kAppName = 'Darter';
const kAppTagline = 'IDE para Dart y Flutter';

// Facetas del logo (triángulos de papel plegado) en un cuadrado unitario.
const _polys = <List<double>>[
  [0.1709, 0.9081, 0.5128, 0.9081, 0.3675, 0.6731],
  [0.1709, 0.9081, 0.3675, 0.6731, 0.0812, 0.7671],
  [0.1709, 0.9081, 0.0812, 0.7671, -0.0000, 0.9808],
  [0.4524, 0.8977, 0.2998, 0.6707, 0.8242, 0.6272],
  [0.2998, 0.6707, 0.4493, 0.5908, 0.8242, 0.6272],
  [0.8242, 0.6272, 0.4493, 0.5908, 0.5637, 0.3849],
  [0.4493, 0.5908, 0.2568, 0.3801, 0.5637, 0.3849],
  [0.5637, 0.3849, 0.2568, 0.3801, 0.6883, 0.2501],
  [0.2568, 0.3801, 0.5595, 0.1131, 0.6883, 0.2501],
  [0.6883, 0.2501, 0.5595, 0.1131, 0.6111, 0.0192],
  [0.6883, 0.2501, 0.6111, 0.0192, 0.5083, 0.1261],
  [0.5595, 0.1131, 0.6111, 0.0192, 0.7564, 0.1944],
  [0.6111, 0.0192, 0.7393, 0.0705, 0.7564, 0.1944],
  [0.6111, 0.0192, 0.7393, 0.0705, 1.0000, 0.0406],
  [0.7393, 0.0705, 0.7564, 0.1944, 1.0000, 0.0406],
];
const _colors = <int>[0xFF8A5EE8, 0xFF4624BC, 0xFF542FE0, 0xFF9D56E0, 0xFF6324B9, 0xFFD743B4, 0xFF862397, 0xFFFF7F71, 0xFFB44A66, 0xFFFFB757, 0xFFC58942, 0xFFA96355, 0xFFFFC04A, 0xFF35F2C4, 0xFF308AA1];
const _eye = <double>[0.6709, 0.1004, 0.0235];

/// Logo de Darter dibujado en vectores: un ave darter de origami.
/// [background]: añade el cuadrado redondeado de icono de app.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 24, this.background = false});
  final double size;
  final bool background;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter(background)));
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.background);
  final bool background;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    var scale = 1.0, off = 0.0;
    if (background) {
      final rr = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(w * 0.225));
      canvas.drawRRect(rr, Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, w), const [Color(0xFF1D1546), Color(0xFF0A0720)]));
      canvas.save();
      canvas.clipRRect(rr);
      canvas.drawPath(Path()..moveTo(0, 0)..lineTo(w * 0.62, 0)..lineTo(0, w * 0.5)..close(), Paint()..color = const Color(0x09FFFFFF));
      canvas.drawPath(Path()..moveTo(w, w)..lineTo(w * 0.34, w)..lineTo(w, w * 0.46)..close(), Paint()..color = const Color(0x107850FF));
      canvas.restore();
      scale = 0.66;
      off = 0.17;
    }
    Offset pt(double x, double y) => Offset((off + x * scale) * w, (off + y * scale) * w);
    final seam = (w / 300).clamp(0.4, 2.0);
    for (var i = 0; i < _polys.length; i++) {
      final p = _polys[i];
      final path = Path()..moveTo(pt(p[0], p[1]).dx, pt(p[0], p[1]).dy)..lineTo(pt(p[2], p[3]).dx, pt(p[2], p[3]).dy)..lineTo(pt(p[4], p[5]).dx, pt(p[4], p[5]).dy)..close();
      canvas.drawPath(path, Paint()..color = Color(_colors[i]));
      canvas.drawPath(path, Paint()..color = Color(_colors[i])..style = PaintingStyle.stroke..strokeWidth = seam..strokeJoin = StrokeJoin.round);
    }
    final e = pt(_eye[0], _eye[1]);
    final r = _eye[2] * scale * w;
    canvas.drawCircle(e, r, Paint()..color = const Color(0xFF0C081E));
    canvas.drawCircle(e.translate(r * 0.28, -r * 0.28), r * 0.36, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.background != background;
}
