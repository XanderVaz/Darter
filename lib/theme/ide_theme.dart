import 'package:flutter/material.dart';

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

class IdeTheme {
  const IdeTheme({
    required this.id, required this.name, required this.dark, required this.bg, required this.side,
    required this.tab, required this.border, required this.accent, required this.text,
    required this.muted, required this.status, required this.syntax,
  });
  final String id, name;
  final bool dark;
  final Color bg, side, tab, border, accent, text, muted, status;
  /// keyword, string, comment, number, type, function (hex sin #)
  final List<String> syntax;

  Color get panel => side;
  Color get onAccent => ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black;

  Map<String, dynamic> get monaco => {
        'base': dark ? 'vs-dark' : 'vs',
        'inherit': true,
        'rules': [
          {'token': 'keyword', 'foreground': syntax[0]},
          {'token': 'string', 'foreground': syntax[1]},
          {'token': 'comment', 'foreground': syntax[2], 'fontStyle': 'italic'},
          {'token': 'number', 'foreground': syntax[3]},
          {'token': 'type', 'foreground': syntax[4]},
          {'token': 'type.identifier', 'foreground': syntax[4]},
          {'token': 'identifier', 'foreground': syntax[5]},
        ],
        'colors': {
          'editor.background': _hex(bg),
          'editor.foreground': _hex(text),
          'editorLineNumber.foreground': _hex(muted),
          'editorLineNumber.activeForeground': _hex(text),
          'editor.lineHighlightBackground': _hex(side),
          'editorCursor.foreground': _hex(accent),
          'editorWidget.background': _hex(side),
          'editorSuggestWidget.background': _hex(side),
          'editorSuggestWidget.border': _hex(border),
          'editorHoverWidget.background': _hex(side),
          'editorHoverWidget.border': _hex(border),
          'editor.selectionBackground': '${_hex(accent)}55',
          'minimap.background': _hex(bg),
        },
      };

  ThemeData get material {
    final b = dark ? Brightness.dark : Brightness.light;
    final cs = ColorScheme.fromSeed(seedColor: accent, brightness: b).copyWith(
      primary: accent, onPrimary: onAccent, surface: side, onSurface: text, outline: border, outlineVariant: border,
    );
    final base = ThemeData(useMaterial3: true, brightness: b, colorScheme: cs, scaffoldBackgroundColor: bg, dividerColor: border);
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
      popupMenuTheme: PopupMenuThemeData(color: side, textStyle: TextStyle(color: text, fontSize: 13)),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true, filled: true, fillColor: bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: accent)),
      ),
    );
  }

  static const all = <IdeTheme>[
    IdeTheme(id: 'dark', name: 'Dark+ (VSCode)', dark: true, bg: Color(0xFF1E1E1E), side: Color(0xFF252526), tab: Color(0xFF2D2D2D), border: Color(0xFF3C3C3C), accent: Color(0xFF0E7AC4), text: Color(0xFFD4D4D4), muted: Color(0xFF858585), status: Color(0xFF007ACC), syntax: ['569CD6', 'CE9178', '6A9955', 'B5CEA8', '4EC9B0', 'DCDCAA']),
    IdeTheme(id: 'flutter', name: 'Flutter Night', dark: true, bg: Color(0xFF0F1B2D), side: Color(0xFF0B1424), tab: Color(0xFF13233B), border: Color(0xFF1E3355), accent: Color(0xFF42A5F5), text: Color(0xFFE3F2FD), muted: Color(0xFF7A93B5), status: Color(0xFF02569B), syntax: ['64B5F6', 'A5D6A7', '5C7A9E', 'FFCC80', '4DD0E1', 'FFF59D']),
    IdeTheme(id: 'tokyo', name: 'Tokyo Night', dark: true, bg: Color(0xFF1A1B26), side: Color(0xFF16161E), tab: Color(0xFF1F2335), border: Color(0xFF292E42), accent: Color(0xFF7AA2F7), text: Color(0xFFC0CAF5), muted: Color(0xFF565F89), status: Color(0xFF3D59A1), syntax: ['BB9AF7', '9ECE6A', '565F89', 'FF9E64', '2AC3DE', '7AA2F7']),
    IdeTheme(id: 'dracula', name: 'Dracula', dark: true, bg: Color(0xFF282A36), side: Color(0xFF21222C), tab: Color(0xFF343746), border: Color(0xFF44475A), accent: Color(0xFFBD93F9), text: Color(0xFFF8F8F2), muted: Color(0xFF6272A4), status: Color(0xFF6D4FB3), syntax: ['FF79C6', 'F1FA8C', '6272A4', 'BD93F9', '8BE9FD', '50FA7B']),
    IdeTheme(id: 'onedark', name: 'One Dark', dark: true, bg: Color(0xFF282C34), side: Color(0xFF21252B), tab: Color(0xFF2C313A), border: Color(0xFF3E4451), accent: Color(0xFF61AFEF), text: Color(0xFFABB2BF), muted: Color(0xFF5C6370), status: Color(0xFF3A7BB8), syntax: ['C678DD', '98C379', '5C6370', 'D19A66', 'E5C07B', '61AFEF']),
    IdeTheme(id: 'light', name: 'Light+', dark: false, bg: Color(0xFFFFFFFF), side: Color(0xFFF3F3F3), tab: Color(0xFFECECEC), border: Color(0xFFD4D4D4), accent: Color(0xFF0066B8), text: Color(0xFF1F1F1F), muted: Color(0xFF6E6E6E), status: Color(0xFF0066B8), syntax: ['0000FF', 'A31515', '008000', '098658', '267F99', '795E26']),
  ];

  static IdeTheme byId(String? id) => all.firstWhere((t) => t.id == id, orElse: () => all.first);
}
