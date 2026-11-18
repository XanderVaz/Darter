import 'dart:convert';

enum ConflictChoice { none, ours, theirs, both, bothReversed, custom }

class TextSeg {
  TextSeg(this.lines);
  final List<String> lines;
}

class ConflictSeg {
  ConflictSeg(this.startLine, this.oursLabel, this.theirsLabel, this.ours, this.base, this.theirs, this.hasBase);
  final int startLine; // línea (1-based) de «<<<<<<<»
  final String oursLabel, theirsLabel;
  final List<String> ours, base, theirs;
  final bool hasBase;
  ConflictChoice choice = ConflictChoice.none;
  String custom = '';

  bool get resolved => choice != ConflictChoice.none;

  List<String> get result {
    switch (choice) {
      case ConflictChoice.ours:
        return ours;
      case ConflictChoice.theirs:
        return theirs;
      case ConflictChoice.both:
        return [...ours, ...theirs];
      case ConflictChoice.bothReversed:
        return [...theirs, ...ours];
      case ConflictChoice.custom:
        return custom.isEmpty ? <String>[] : const LineSplitter().convert(custom);
      case ConflictChoice.none:
        return <String>[];
    }
  }
}

class MergeDoc {
  MergeDoc(this.segs, this.eol, this.endsWithNewline);
  final List<Object> segs; // TextSeg | ConflictSeg
  final String eol;
  final bool endsWithNewline;

  List<ConflictSeg> get conflicts => segs.whereType<ConflictSeg>().toList();
  bool get allResolved => conflicts.every((c) => c.resolved);

  String build() {
    final out = <String>[];
    for (final s in segs) {
      if (s is TextSeg) {
        out.addAll(s.lines);
      } else if (s is ConflictSeg) {
        if (s.resolved) {
          out.addAll(s.result);
        } else {
          out.add('<<<<<<< ${s.oursLabel}'.trimRight());
          out.addAll(s.ours);
          if (s.hasBase) {
            out.add('||||||| base');
            out.addAll(s.base);
          }
          out.add('=======');
          out.addAll(s.theirs);
          out.add('>>>>>>> ${s.theirsLabel}'.trimRight());
        }
      }
    }
    return out.join(eol) + (endsWithNewline && out.isNotEmpty ? eol : '');
  }
}

/// Analiza un texto con marcas de conflicto (<<<<<<<, |||||||, =======, >>>>>>>).
MergeDoc parseMerge(String text) {
  final eol = text.contains('\r\n') ? '\r\n' : '\n';
  final endsNl = text.endsWith('\n');
  var body = endsNl ? text.substring(0, text.length - 1) : text;
  if (eol == '\r\n' && body.endsWith('\r')) body = body.substring(0, body.length - 1);
  final lines = body.isEmpty ? <String>[] : body.split(eol);

  final segs = <Object>[];
  var plain = <String>[];
  var state = 0; // 0 normal, 1 ours, 2 base, 3 theirs
  var start = 0;
  var oursLabel = '', theirsLabel = '';
  var ours = <String>[], base = <String>[], theirs = <String>[];
  var hasBase = false;

  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (state == 0) {
      if (RegExp(r'^<<<<<<<(\s|$)').hasMatch(l)) {
        if (plain.isNotEmpty) {
          segs.add(TextSeg(plain));
          plain = [];
        }
        state = 1;
        start = i + 1;
        oursLabel = l.length > 8 ? l.substring(8).trim() : '';
        ours = [];
        base = [];
        theirs = [];
        hasBase = false;
      } else {
        plain.add(l);
      }
    } else if (state == 1 && l.startsWith('|||||||')) {
      state = 2;
      hasBase = true;
    } else if ((state == 1 || state == 2) && RegExp(r'^=======\s*$').hasMatch(l)) {
      state = 3;
    } else if (state == 3 && l.startsWith('>>>>>>>')) {
      theirsLabel = l.length > 8 ? l.substring(8).trim() : '';
      segs.add(ConflictSeg(start, oursLabel, theirsLabel, ours, base, theirs, hasBase));
      state = 0;
    } else if (state == 1) {
      ours.add(l);
    } else if (state == 2) {
      base.add(l);
    } else {
      theirs.add(l);
    }
  }
  if (state != 0) {
    // conflicto sin cerrar: no tocar nada
    return MergeDoc([TextSeg(lines)], eol, endsNl);
  }
  if (plain.isNotEmpty) segs.add(TextSeg(plain));
  return MergeDoc(segs, eol, endsNl);
}
