import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import '../state/ide_state.dart';
import 'command_palette.dart';
import 'diff_view.dart';
import 'logo.dart';
import 'common.dart';
import 'create_project.dart';

const _monacoVersion = '0.52.0';
const _htmlTpl = r'''
<html><head><style>.bp-glyph{background:#e51400;border-radius:50%;width:10px!important;height:10px!important;margin:5px 0 0 5px}.dbg-arrow{background:#ffcc00;width:10px!important;height:10px!important;margin:5px 0 0 5px;clip-path:polygon(0 0,100% 50%,0 100%)}.dbg-line{background:rgba(255,204,0,.22)}.cf-mark{background:rgba(128,128,128,.28)}.cf-cur{background:rgba(64,200,174,.20)}.cf-inc{background:rgba(64,166,255,.20)}.gt-add{border-left:3px solid #2ea043;margin-left:3px}.gt-mod{border-left:3px solid #1f6feb;margin-left:3px}.gt-del{border-left:3px solid #f85149;margin-left:3px}</style></head><body style="margin:0;background:__BG__"><div id="c" style="height:100vh"></div>
<script src="https://cdn.jsdelivr.net/npm/monaco-editor@__V__/min/vs/loader.js"></script>
<script>
const call=(...a)=>window.flutter_inappwebview.callHandler(...a);
const KIND=[18,18,0,1,2,3,4,5,7,8,9,12,13,15,17,25,19,20,21,23,16,14,6,10,11,24];
let suppress=false;
const SNIP=[
["stless","Flutter StatelessWidget","class ${1:MyWidget} extends StatelessWidget {\n  const ${1:MyWidget}({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return ${2:const Placeholder()};\n  }\n}"],
["stful","Flutter StatefulWidget","class ${1:MyWidget} extends StatefulWidget {\n  const ${1:MyWidget}({super.key});\n\n  @override\n  State<${1:MyWidget}> createState() => _${1:MyWidget}State();\n}\n\nclass _${1:MyWidget}State extends State<${1:MyWidget}> {\n  @override\n  Widget build(BuildContext context) {\n    return ${2:const Placeholder()};\n  }\n}"],
["initS","initState()","@override\nvoid initState() {\n  super.initState();\n  $0\n}"],
["disp","dispose()","@override\nvoid dispose() {\n  $0\n  super.dispose();\n}"],
["setS","setState","setState(() {\n  $0\n});"],
["main","main() con runApp","void main() {\n  runApp(const ${1:MyApp}());\n}"],
["mapp","MaterialApp","MaterialApp(\n  title: \"${1:App}\",\n  theme: ThemeData(useMaterial3: true),\n  home: ${2:const Placeholder()},\n)"],
["scaf","Scaffold","Scaffold(\n  appBar: AppBar(title: const Text(\"${1:Titulo}\")),\n  body: ${2:const Placeholder()},\n)"],
["lvb","ListView.builder","ListView.builder(\n  itemCount: ${1:items.length},\n  itemBuilder: (context, index) {\n    return ${2:const SizedBox()};\n  },\n)"],
["futb","FutureBuilder","FutureBuilder<${1:Object}>(\n  future: ${2:future},\n  builder: (context, snapshot) {\n    if (snapshot.connectionState != ConnectionState.done) {\n      return const Center(child: CircularProgressIndicator());\n    }\n    return ${3:const SizedBox()};\n  },\n)"],
["strb","StreamBuilder","StreamBuilder<${1:Object}>(\n  stream: ${2:stream},\n  builder: (context, snapshot) {\n    return ${3:const SizedBox()};\n  },\n)"],
["col","Column","Column(\n  children: [\n    $0\n  ],\n)"],
["row","Row","Row(\n  children: [\n    $0\n  ],\n)"],
["cont","Container","Container(\n  padding: const EdgeInsets.all(${1:16}),\n  child: ${2:const SizedBox()},\n)"],
["notif","ChangeNotifier","class ${1:Model} extends ChangeNotifier {\n  $0\n}"],
["tw","testWidgets","testWidgets(\"${1:descripcion}\", (WidgetTester tester) async {\n  $0\n});"],
];
require.config({paths:{vs:'https://cdn.jsdelivr.net/npm/monaco-editor@__V__/min/vs'}});
require(['vs/editor/editor.main'],()=>{
  window.models={};
  const callF=(...a)=>{window.flushNow();return call(...a);};
  const flushChange=(m)=>{
    if(!m||!m.__pending)return;
    clearTimeout(m.__s);m.__pending=false;m.__dirtySent=false;
    call('changed',m.__path,m.getValue());
  };
  const queueChange=(m)=>{
    if(!m.__dirtySent){m.__dirtySent=true;call('dirty',m.__path);}
    m.__pending=true;clearTimeout(m.__s);
    m.__s=setTimeout(()=>flushChange(m),250);
  };
  window.flushNow=()=>{flushChange(ed.getModel());};
  window.ed=monaco.editor.create(document.getElementById('c'),{theme:'vs-dark',automaticLayout:true,fontSize:14,
    minimap:{enabled:true},bracketPairColorization:{enabled:true},smoothScrolling:false,accessibilitySupport:'off',quickSuggestionsDelay:120,scrollBeyondLastLine:false,
    glyphMargin:true,stickyScroll:{enabled:true},fixedOverflowWidgets:true,quickSuggestions:{other:true,comments:false,strings:true},model:null});
  monaco.languages.registerCompletionItemProvider('dart',{triggerCharacters:['.','(',':'],
    provideCompletionItems:async(m,pos,ctx,token)=>{
      flushChange(m);
      const r=await call('lspCompletion',m.__path,pos.lineNumber-1,pos.column-1);
      if(token&&token.isCancellationRequested)return {suggestions:[]};
      const w=m.getWordUntilPosition(pos);
      const range={startLineNumber:pos.lineNumber,endLineNumber:pos.lineNumber,startColumn:w.startColumn,endColumn:w.endColumn};
      const sn=SNIP.map(s=>({label:s[0],detail:s[1],kind:monaco.languages.CompletionItemKind.Snippet,insertText:s[2],insertTextRules:monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet,sortText:'0'+s[0],range}));
      const us=(window.USNIP||[]).map(u=>({label:u.prefix,detail:u.desc||'Snippet propio',kind:monaco.languages.CompletionItemKind.Snippet,insertText:u.body,insertTextRules:monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet,sortText:'0'+u.prefix,range}));
      return {suggestions:[...sn,...us,...(r||[]).map(i=>({label:i.label,kind:KIND[i.kind]??18,insertText:i.insertText,detail:i.detail,sortText:i.sort,range}))]};
    }});
  monaco.languages.registerHoverProvider('dart',{provideHover:async(m,pos)=>{
    flushChange(m);const t=await call('lspHover',m.__path,pos.lineNumber-1,pos.column-1);
    return t?{contents:[{value:t}]}:null;}});
  const goDef=()=>{const pos=ed.getPosition(),m=ed.getModel();if(m&&pos){flushChange(m);call('lspDefinition',m.__path,pos.lineNumber-1,pos.column-1);}};
  ed.addCommand(monaco.KeyCode.F12,goDef);
  ed.onMouseDown(e=>{if((e.event.ctrlKey||e.event.metaKey)&&e.event.leftButton&&e.target.position){ed.setPosition(e.target.position);goDef();}});
  ed.addCommand(monaco.KeyMod.Alt|monaco.KeyMod.Shift|monaco.KeyCode.KeyF,()=>callF('format'));
  const selRange=()=>{const s=ed.getSelection();return [s.startLineNumber-1,s.startColumn-1,s.endLineNumber-1,s.endColumn-1];};
  ed.addCommand(monaco.KeyMod.CtrlCmd|monaco.KeyCode.Period,()=>{const m=ed.getModel();if(m)callF('codeActions',m.__path,...selRange());});
  ed.addCommand(monaco.KeyCode.F2,()=>{const m=ed.getModel(),pos=ed.getPosition();if(!m||!pos)return;const w=m.getWordAtPosition(pos);callF('rename',m.__path,pos.lineNumber-1,pos.column-1,w?w.word:'');});
  ed.addCommand(monaco.KeyMod.Shift|monaco.KeyCode.F12,()=>{const m=ed.getModel(),pos=ed.getPosition();if(m&&pos)callF('references',m.__path,pos.lineNumber-1,pos.column-1);});
  ed.addCommand(monaco.KeyMod.Alt|monaco.KeyMod.Shift|monaco.KeyCode.KeyO,()=>callF('organizeImports'));
  ed.addCommand(monaco.KeyMod.CtrlCmd|monaco.KeyMod.Shift|monaco.KeyCode.KeyO,()=>callF('symbols'));
  const bpIds={};let dbg={m:null,ids:[]};
  const conflictIds={};
  const gutterIds={};
  window.setGutter=(p,rs)=>{const m=models[p];if(!m)return;gutterIds[p]=m.deltaDecorations(gutterIds[p]||[],rs.map(r=>({range:new monaco.Range(r[0],1,r[1],1),options:{isWholeLine:true,linesDecorationsClassName:r[2]===0?'gt-add':(r[2]===1?'gt-mod':'gt-del')}})));};
  window.USNIP=[];
  window.setUserSnippets=(a)=>{window.USNIP=a||[];};
  const markConflicts=(m)=>{
    const p=m.__path;
    if(!(conflictIds[p]&&conflictIds[p].length)&&m.findMatches('<<<<<<<',false,false,true,null,false,1).length===0)return;
    const lines=m.getLinesContent(),decos=[];let st=0,start=0;
    const mk=(a,b,c)=>({range:new monaco.Range(a,1,b,1),options:{isWholeLine:true,className:c}});
    lines.forEach((t,i)=>{const ln=i+1;
      if(st===0){if(/^<<<<<<<(\s|$)/.test(t)){st=1;start=ln+1;decos.push(mk(ln,ln,'cf-mark'));}}
      else if(st===1||st===2){
        if(st===1&&/^\|\|\|\|\|\|\|/.test(t)){if(ln-1>=start)decos.push(mk(start,ln-1,'cf-cur'));st=2;decos.push(mk(ln,ln,'cf-mark'));}
        else if(/^=======\s*$/.test(t)){if(st===1&&ln-1>=start)decos.push(mk(start,ln-1,'cf-cur'));st=3;start=ln+1;decos.push(mk(ln,ln,'cf-mark'));}
      }else if(st===3){if(/^>>>>>>>/.test(t)){if(ln-1>=start)decos.push(mk(start,ln-1,'cf-inc'));decos.push(mk(ln,ln,'cf-mark'));st=0;}}
    });
    conflictIds[p]=m.deltaDecorations(conflictIds[p]||[],decos);
  };
  window.setBps=(p,lines)=>{const m=models[p];if(!m)return;bpIds[p]=m.deltaDecorations(bpIds[p]||[],lines.map(l=>({range:new monaco.Range(l,1,l,1),options:{glyphMarginClassName:'bp-glyph'}})));};
  window.setDbgLine=(p,l)=>{if(dbg.m){try{dbg.m.deltaDecorations(dbg.ids,[]);}catch(e){}}dbg={m:null,ids:[]};if(!p)return;const m=models[p];if(!m)return;dbg={m:m,ids:m.deltaDecorations([],[{range:new monaco.Range(l,1,l,1),options:{isWholeLine:true,className:'dbg-line',glyphMarginClassName:'dbg-arrow'}}])};};
  ed.onMouseDown(e=>{if(e.target.type===monaco.editor.MouseTargetType.GUTTER_GLYPH_MARGIN&&e.target.position){const m=ed.getModel();if(m)call('toggleBp',m.__path,e.target.position.lineNumber);}});
  ed.addCommand(monaco.KeyCode.F9,()=>{const m=ed.getModel(),pos=ed.getPosition();if(m&&pos)call('toggleBp',m.__path,pos.lineNumber);});
  ed.addCommand(monaco.KeyCode.F5,()=>call('dbg','f5'));
  ed.addCommand(monaco.KeyCode.F10,()=>call('dbg','next'));
  ed.addCommand(monaco.KeyCode.F11,()=>call('dbg','in'));
  ed.addCommand(monaco.KeyMod.Shift|monaco.KeyCode.F11,()=>call('dbg','out'));
  ed.addCommand(monaco.KeyMod.Shift|monaco.KeyCode.F5,()=>call('dbg','stop'));
  ed.addCommand(monaco.KeyMod.CtrlCmd|monaco.KeyMod.Shift|monaco.KeyCode.KeyT,()=>call('dbg','gotest'));
  ed.addCommand(monaco.KeyMod.CtrlCmd|monaco.KeyCode.Equal,()=>call('zoom',1));
  ed.addCommand(monaco.KeyMod.CtrlCmd|monaco.KeyCode.Minus,()=>call('zoom',-1));
  ed.addCommand(monaco.KeyMod.CtrlCmd|monaco.KeyCode.Digit0,()=>call('zoom',0));
  const MC={red:'F44336',pink:'E91E63',purple:'9C27B0',deepPurple:'673AB7',indigo:'3F51B5',blue:'2196F3',lightBlue:'03A9F4',cyan:'00BCD4',teal:'009688',green:'4CAF50',lightGreen:'8BC34A',lime:'CDDC39',yellow:'FFEB3B',amber:'FFC107',orange:'FF9800',deepOrange:'FF5722',brown:'795548',grey:'9E9E9E',blueGrey:'607D8B',black:'000000',white:'FFFFFF',redAccent:'FF5252',pinkAccent:'FF4081',purpleAccent:'E040FB',indigoAccent:'536DFE',blueAccent:'448AFF',cyanAccent:'18FFFF',tealAccent:'64FFDA',greenAccent:'69F0AE',amberAccent:'FFD740',orangeAccent:'FFAB40',yellowAccent:'FFFF00'};
  const hex2c=(h,a)=>({red:parseInt(h.slice(0,2),16)/255,green:parseInt(h.slice(2,4),16)/255,blue:parseInt(h.slice(4,6),16)/255,alpha:a});
  monaco.languages.registerColorProvider('dart',{
    provideDocumentColors:(m)=>{
      const out=[];
      m.getLinesContent().forEach((t,i)=>{
        const ln=i+1;let r;
        const re1=/Color\(\s*0x([0-9A-Fa-f]{8})\s*\)/g;
        while((r=re1.exec(t))){const st=r.index+r[0].indexOf('0x'),h=r[1];
          out.push({color:hex2c(h.slice(2),parseInt(h.slice(0,2),16)/255),range:{startLineNumber:ln,startColumn:st+1,endLineNumber:ln,endColumn:st+11}});}
        const re2=/Colors\.([a-zA-Z]+)(?![\w(])/g;
        while((r=re2.exec(t))){const h=MC[r[1]];
          if(h)out.push({color:hex2c(h,1),range:{startLineNumber:ln,startColumn:r.index+1,endLineNumber:ln,endColumn:r.index+1+r[0].length}});}
      });
      return out;
    },
    provideColorPresentations:(m,info)=>{
      const c=info.color,to=v=>Math.round(v*255).toString(16).padStart(2,'0').toUpperCase();
      const isHex=m.getValueInRange(new monaco.Range(info.range.startLineNumber,info.range.startColumn,info.range.endLineNumber,info.range.startColumn+2))==='0x';
      return isHex?[{label:'0x'+to(c.alpha)+to(c.red)+to(c.green)+to(c.blue)}]:[];
    }
  });
  monaco.languages.registerSignatureHelpProvider('dart',{
    signatureHelpTriggerCharacters:['(',','],signatureHelpRetriggerCharacters:[')'],
    provideSignatureHelp:async(m,pos)=>{
      flushChange(m);
      const r=await call('lspSignature',m.__path,pos.lineNumber-1,pos.column-1);
      if(!r)return null;
      return {value:{signatures:r.signatures.map(s=>({label:s.label,documentation:s.doc?{value:s.doc}:undefined,parameters:(s.params||[]).map(p=>({label:p.label,documentation:p.doc?{value:p.doc}:undefined})),activeParameter:s.active==null?undefined:s.active})),activeSignature:r.activeSignature,activeParameter:r.activeParameter},dispose:()=>{}};
    }
  });
  const lensCmd=ed.addCommand(0,(acc,kind,path,name)=>callF('lens',kind,path,name||''));
  monaco.languages.registerCodeLensProvider('dart',{
    provideCodeLenses:(m)=>{
      const lenses=[];
      m.getLinesContent().forEach((t,i)=>{
        const ln=i+1,range={startLineNumber:ln,startColumn:1,endLineNumber:ln,endColumn:1};
        if(/^\s*(Future<void>|void)\s+main\s*\(/.test(t)){
          lenses.push({range,command:{id:lensCmd,title:'▶ Run',arguments:['run',m.__path,'']}});
          lenses.push({range,command:{id:lensCmd,title:'🐞 Debug',arguments:['debug',m.__path,'']}});
        }
        const mt=t.match(/^\s*(testWidgets|test|group)\(\s*(['"])(.*?)\2/);
        if(mt){lenses.push({range,command:{id:lensCmd,title:mt[1]==='group'?'▶ Run group':'▶ Run test',arguments:['test',m.__path,mt[3]]}});lenses.push({range,command:{id:lensCmd,title:'🐞 Debug',arguments:['debugtest',m.__path,mt[3]]}});}
      });
      return {lenses,dispose:()=>{}};
    },
    resolveCodeLens:(m,l)=>l
  });
  monaco.languages.registerCodeLensProvider('*',{
    provideCodeLenses:(m)=>{
      if(m.findMatches('<<<<<<<',false,false,true,null,false,1).length===0)return {lenses:[],dispose:()=>{}};
      const lenses=[];
      m.getLinesContent().forEach((t,i)=>{
        if(/^<<<<<<<(\s|$)/.test(t)){
          const ln=i+1,range={startLineNumber:ln,startColumn:1,endLineNumber:ln,endColumn:1};
          lenses.push({range,command:{id:lensCmd,title:'✔ Aceptar actual',arguments:['cur',m.__path,String(ln)]}});
          lenses.push({range,command:{id:lensCmd,title:'✔ Aceptar entrante',arguments:['inc',m.__path,String(ln)]}});
          lenses.push({range,command:{id:lensCmd,title:'✔ Aceptar ambos',arguments:['both',m.__path,String(ln)]}});
          lenses.push({range,command:{id:lensCmd,title:'⇄ Resolver…',arguments:['resolver',m.__path,'']}});
        }
      });
      return {lenses,dispose:()=>{}};
    },
    resolveCodeLens:(m,l)=>l
  });
  ed.addCommand(monaco.KeyMod.CtrlCmd|monaco.KeyCode.KeyS,()=>{window.flushNow();call('save');});
  window.openDoc=(p,t,l)=>{let m=models[p];
    if(!m){m=models[p]=monaco.editor.createModel(t,l,monaco.Uri.file(p));m.__path=p;m.updateOptions({tabSize:2,insertSpaces:true});
      m.onDidChangeContent(()=>{if(!suppress)queueChange(m);clearTimeout(m.__c);m.__c=setTimeout(()=>markConflicts(m),300);clearTimeout(m.__t);m.__t=setTimeout(()=>{const ids=bpIds[p];if(ids&&ids.length)call('bpsChanged',p,ids.map(id=>{const r=m.getDecorationRange(id);return r?r.startLineNumber:0;}).filter(x=>x>0));},400);});}
    ed.setModel(m);markConflicts(m);};
  window.closeDoc=p=>{const m=models[p];if(!m)return;if(ed.getModel()===m)ed.setModel(null);m.dispose();delete models[p];};
  window.setText=(p,t)=>{const m=models[p];if(!m)return;suppress=true;m.setValue(t);suppress=false;};
  window.setMarkers=(p,ms)=>{const m=models[p];if(m)monaco.editor.setModelMarkers(m,'dart',ms);};
  window.reveal=(l,c)=>{const pos={lineNumber:l,column:c};ed.setPosition(pos);ed.revealPositionInCenter(pos);ed.focus();};
  window.applySettings=(fs,mm,wrap,fam,lig,tab)=>{ed.updateOptions({fontSize:fs,minimap:{enabled:mm},wordWrap:wrap?'on':'off',fontFamily:fam?fam:'Consolas, "Courier New", monospace',fontLigatures:lig,tabSize:tab});monaco.editor.getModels().forEach(m=>m.updateOptions({tabSize:tab}));};
  window.applyTheme=(def,id)=>{monaco.editor.defineTheme(id,def);monaco.editor.setTheme(id);document.body.style.background=def.colors['editor.background'];};
  call('ready');
});
</script></body></html>''';

String _lang(String path) {
  final e = path.split('.').last.toLowerCase();
  return const {
        'dart': 'dart', 'yaml': 'yaml', 'yml': 'yaml', 'json': 'json', 'md': 'markdown', 'xml': 'xml', 'html': 'html',
        'css': 'css', 'js': 'javascript', 'kt': 'kotlin', 'swift': 'swift', 'gradle': 'groovy', 'sh': 'shell',
      }[e] ??
      'plaintext';
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String _page(String bg, String? base) {
  final src = base == null ? 'https://cdn.jsdelivr.net/npm/monaco-editor@$_monacoVersion/min/vs' : '$base/vs';
  return _htmlTpl.replaceAll('https://cdn.jsdelivr.net/npm/monaco-editor@__V__/min/vs', src).replaceAll('__BG__', bg);
}

List<Map<String, dynamic>> _markers(List<Diag> ds) => [
      for (final d in ds)
        {
          'startLineNumber': d.line + 1, 'startColumn': d.col + 1, 'endLineNumber': d.endLine + 1, 'endColumn': d.endCol + 1,
          'message': d.message, 'severity': const {1: 8, 2: 4, 3: 2, 4: 1}[d.severity] ?? 2,
        }
    ];

class EditorArea extends StatefulWidget {
  const EditorArea(this.s, {super.key});
  final IdeState s;
  @override
  State<EditorArea> createState() => _EditorAreaState();
}

class _EditorAreaState extends State<EditorArea> {
  InAppWebViewController? _c;
  bool _ready = false;
  String? _shown, _themeId;
  int _setRev = -1;
  int _monacoRev = 0;
  IdeState get s => widget.s;

  void _js(String src) => _c?.evaluateJavascript(source: src);

  int _i(dynamic v) => (v as num).toInt();

  IconData _kindIcon(String k) => k.startsWith('quickfix') ? Icons.lightbulb_outline : k.startsWith('refactor') ? Icons.auto_fix_high : k.startsWith('source') ? Icons.sort : Icons.bolt;

  Future<void> _codeActions(List a) async {
    final acts = await s.lspCodeActions(a[0], _i(a[1]), _i(a[2]), _i(a[3]), _i(a[4]));
    if (!mounted) return;
    if (acts.isEmpty) {
      s.info('Sin acciones de código disponibles en esta posición');
      return;
    }
    showCommandPalette(context, s, pure: true, placeholder: 'Acciones de código (${acts.length})…', commands: [
      for (final act in acts) PaletteCmd('${act['title']}', _kindIcon('${act['kind'] ?? ''}'), () => s.applyCodeAction(act)),
    ]);
  }

  Future<void> _rename(List a) async {
    final old = '${a[3]}';
    final n = await promptText(context, s, 'Renombrar símbolo', initial: old);
    if (n == null || n == old) return;
    await s.lspRename(a[0], _i(a[1]), _i(a[2]), n);
  }

  Future<void> _references(List a) async {
    final refs = await s.lspReferences(a[0], _i(a[1]), _i(a[2]));
    if (!mounted) return;
    if (refs.isEmpty) {
      s.info('Sin referencias');
      return;
    }
    showCommandPalette(context, s, pure: true, placeholder: '${refs.length} referencias', commands: [
      for (final r in refs)
        PaletteCmd('${p.relative(r['path'] as String, from: s.root ?? '.')}:${_i(r['line']) + 1}', Icons.link,
            () => s.openFile(r['path'] as String, line: _i(r['line']) + 1, col: _i(r['col']) + 1),
            hint: s.lineText(r['path'] as String, _i(r['line']))),
    ]);
  }

  Future<void> _symbols() async {
    final d = s.current;
    if (d == null) return;
    final list = await s.lspSymbols(d.path);
    if (!mounted || list.isEmpty) return;
    showCommandPalette(context, s, pure: true, placeholder: 'Ir a símbolo…', commands: [
      for (final e in list)
        PaletteCmd('${'   ' * _i(e['depth'])}${e['name']}', Icons.functions, () => s.openFile(d.path, line: _i(e['line']) + 1, col: _i(e['col']) + 1), hint: 'línea ${_i(e['line']) + 1}'),
    ]);
  }

  Future<void> _closeTab(int i) async {
    final d = s.docs[i];
    if (d.dirty) {
      final r = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: s.theme.panel,
          surfaceTintColor: Colors.transparent,
          title: const Text('Cambios sin guardar', style: TextStyle(fontSize: 16)),
          content: Text('¿Guardar los cambios de "${d.name}" antes de cerrar?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('No guardar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Guardar')),
          ],
        ),
      );
      if (r == null || r == 'cancel') return;
      if (r == 'save') await s.saveDoc(d);
    }
    if (i < s.docs.length && s.docs[i] == d) s.closeDoc(i);
  }

  Future<void> _tabMenu(Offset pos, int i) async {
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(value: 'close', child: Text('Cerrar')),
        PopupMenuItem(value: 'others', child: Text('Cerrar otras (mantiene las modificadas)')),
        PopupMenuItem(value: 'all', child: Text('Cerrar todas (mantiene las modificadas)')),
        PopupMenuItem(value: 'history', child: Text('Historial del archivo (Git)')),
        PopupMenuItem(value: 'diffhead', child: Text('Comparar con HEAD')),
        PopupMenuItem(value: 'diffsaved', child: Text('Comparar con el guardado')),
        PopupMenuItem(value: 'copy', child: Text('Copiar ruta')),
      ],
    );
    if (v == null) return;
    switch (v) {
      case 'close':
        _closeTab(i);
      case 'others':
        s.closeOthers(i);
      case 'all':
        s.closeAllDocs();
      case 'copy':
        Clipboard.setData(ClipboardData(text: s.docs[i].path));
      case 'history':
        showFileHistory(context, s, s.docs[i].path);
      case 'diffhead':
        {
          final d = s.docs[i];
          final x = await s.gitHeadVsWorking(d.path);
          if (mounted) showDiffDialog(context, s, title: '${d.name} · HEAD ↔ actual', path: d.path, original: x.a, modified: x.b);
        }
      case 'diffsaved':
        {
          final d = s.docs[i];
          showDiffDialog(context, s, title: '${d.name} · guardado ↔ editor', path: d.path, original: s.diskText(d.path), modified: d.content);
        }
    }
  }

  @override
  void initState() {
    super.initState();
    s.addListener(_sync);
    _monacoRev = s.monacoRev;
    s.monacoServer.pageBuilder = (bg) => _page(bg, s.monacoBase);
    s.onMarkers = (path, list) {
      if (_ready) _js('setMarkers(${jsonEncode(path)},${jsonEncode(_markers(list))})');
    };
    s.onGutter = (path, rs) {
      if (_ready) _js('setGutter(${jsonEncode(path)},${jsonEncode(rs)})');
    };
    s.onBreakpoints = (path, lines) {
      if (_ready) _js('setBps(${jsonEncode(path)},${jsonEncode(lines)})');
    };
    s.onDebugLine = (path, line) {
      if (_ready) _js(path == null ? 'setDbgLine(null,0)' : 'setDbgLine(${jsonEncode(path)},$line)');
    };
    s.onDocClosed = (path) {
      if (_shown != null && norm(_shown!) == norm(path)) _shown = null;
      if (_ready) _js('closeDoc(${jsonEncode(path)})');
      _plainCtl.remove(path)?.dispose();
    };
    s.onExternalChange = (path, text) {
      if (!_useWeb) {
        final c = _plainCtl[path];
        if (c != null && c.text != text) c.text = text;
      } else if (_ready) {
        _js('setText(${jsonEncode(path)},${jsonEncode(text)})');
      }
    };
  }

  @override
  void dispose() {
    s.removeListener(_sync);
    s.onMarkers = s.onDocClosed = s.onExternalChange = s.onBreakpoints = s.onDebugLine = s.onGutter = null;
    for (final c in _plainCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _sync() {
    if (_monacoRev != s.monacoRev) {
      _monacoRev = s.monacoRev;
      _ready = false;
      _shown = null;
      _themeId = null;
      _setRev = -1;
      return;
    }
    if (!_ready) return;
    if (_themeId != s.theme.id) {
      _themeId = s.theme.id;
      _js('applyTheme(${jsonEncode(s.theme.monaco)},"${s.theme.id}")');
    }
    if (_setRev != s.settingsRev) {
      _setRev = s.settingsRev;
      _js('applySettings(${s.fontSize},${s.minimap},${s.wordWrap},${jsonEncode(s.fontFamily)},${s.fontLigatures},${s.tabSize})');
      _js('setUserSnippets(${jsonEncode(s.userSnippets)})');
    }
    final d = s.current;
    if (d == null || d.isImage) return;
    if (_shown != d.path) {
      _shown = d.path;
      _js('openDoc(${jsonEncode(d.path)},${jsonEncode(d.content)},"${_lang(d.path)}")');
      final ds = s.diags[norm(d.path)];
      if (ds != null) _js('setMarkers(${jsonEncode(d.path)},${jsonEncode(_markers(ds))})');
      final bps = s.breakpoints[norm(d.path)];
      if (bps != null && bps.isNotEmpty) _js('setBps(${jsonEncode(d.path)},${jsonEncode(bps.toList())})');
      final dl = s.debugLine;
      if (dl != null && norm(dl.path) == norm(d.path)) _js('setDbgLine(${jsonEncode(d.path)},${dl.line})');
      s.refreshGutter(d.path);
    }
    final r = s.reveal;
    if (r != null && norm(r.path) == norm(d.path)) {
      s.reveal = null;
      _js('reveal(${r.line},${r.col})');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([s, s.dirtyRev, s.diagRev]),
        builder: (_, __) {
          final t = s.theme;
          return Column(children: [
            Container(
              height: 36,
              color: t.side,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (var i = 0; i < s.docs.length; i++)
                  Tooltip(
                    message: s.docs[i].path,
                    child: InkWell(
                      onTap: () => s.setActive(i),
                      onSecondaryTapDown: (d) => _tabMenu(d.globalPosition, i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: i == s.active ? t.bg : t.tab,
                          border: Border(top: BorderSide(width: 2, color: i == s.active ? t.accent : Colors.transparent), right: BorderSide(color: t.border)),
                        ),
                        child: Row(children: [
                          Icon(fileIcon(s.docs[i].name), size: 14, color: fileColor(s.docs[i].name, t)),
                          const SizedBox(width: 6),
                          Text(s.docs[i].name, style: TextStyle(fontSize: 13, color: (s.diags[norm(s.docs[i].path)] ?? const <Diag>[]).any((x) => x.severity == 1) ? Colors.redAccent : (i == s.active ? t.text : t.muted))),
                          const SizedBox(width: 8),
                          InkWell(onTap: () => _closeTab(i), child: Icon(s.docs[i].dirty ? Icons.circle : Icons.close, size: s.docs[i].dirty ? 10 : 14, color: t.muted)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
            if (s.current != null && s.root != null)
              Container(
                width: double.infinity,
                color: t.bg,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                child: Text(p.split(p.relative(s.current!.path, from: s.root!)).join('  ›  '), style: TextStyle(fontSize: 11.5, color: t.muted)),
              ),
            Expanded(
              child: Stack(children: [
                _editorSurface(t),
                if (s.current?.isImage == true)
                  Positioned.fill(
                    child: Container(
                      color: t.bg,
                      child: InteractiveViewer(maxScale: 8, child: Center(child: Image.file(File(s.current!.path), errorBuilder: (_, __, ___) => const Text('No se puede mostrar la imagen')))),
                    ),
                  ),
                if (s.docs.isEmpty) Positioned.fill(child: _welcome(context, t)),
              ]),
            ),
          ]);
        },
      );

  Widget? _wv;
  int _wvRev = -1;
  final _plainCtl = <String, TextEditingController>{};

  bool get _useWeb => !Platform.isLinux;

  /// El WebView se crea una sola vez (y solo se recrea si cambia Monaco): evita trabajo extra en cada redibujado.
  Widget _editorSurface(t) {
    if (!_useWeb) return _plainEditor(t);
    if (_wv == null || _wvRev != s.monacoRev) {
      _wvRev = s.monacoRev;
      _wv = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerUp: (_) => _js('window.ed&&window.ed.focus()'),
        child: InAppWebView(
                  key: ValueKey(s.monacoRev),
                  initialData: s.monacoBase == null ? InAppWebViewInitialData(data: _page(_hex(t.bg), null), baseUrl: WebUri('https://localhost/')) : null,
                  initialUrlRequest: s.monacoBase == null ? null : URLRequest(url: WebUri('${s.monacoBase}/editor.html?bg=${Uri.encodeComponent(_hex(t.bg))}')),
                  onPermissionRequest: (c, req) async => PermissionResponse(resources: req.resources, action: PermissionResponseAction.GRANT),
                  onWebViewCreated: (c) {
                    _c = c;
                    c.addJavaScriptHandler(handlerName: 'ready', callback: (_) {
                      _ready = true;
                      _sync();
                    });
                    c.addJavaScriptHandler(handlerName: 'save', callback: (_) => s.save());
                    c.addJavaScriptHandler(handlerName: 'format', callback: (_) => s.formatCurrent());
                    c.addJavaScriptHandler(handlerName: 'changed', callback: (a) => s.onEdit(a[0], a[1]));
                    c.addJavaScriptHandler(handlerName: 'dirty', callback: (a) => s.markDirty('${a[0]}'));
                    c.addJavaScriptHandler(handlerName: 'lspCompletion', callback: (a) => s.lspCompletion(a[0], (a[1] as num).toInt(), (a[2] as num).toInt()));
                    c.addJavaScriptHandler(handlerName: 'lspHover', callback: (a) => s.lspHover(a[0], (a[1] as num).toInt(), (a[2] as num).toInt()));
                    c.addJavaScriptHandler(handlerName: 'lspDefinition', callback: (a) => s.lspDefinition(a[0], (a[1] as num).toInt(), (a[2] as num).toInt()));
                    c.addJavaScriptHandler(handlerName: 'lspSignature', callback: (a) => s.lspSignature(a[0], _i(a[1]), _i(a[2])));
                    c.addJavaScriptHandler(handlerName: 'codeActions', callback: (a) => _codeActions(a));
                    c.addJavaScriptHandler(handlerName: 'rename', callback: (a) => _rename(a));
                    c.addJavaScriptHandler(handlerName: 'references', callback: (a) => _references(a));
                    c.addJavaScriptHandler(handlerName: 'organizeImports', callback: (_) => s.organizeImports());
                    c.addJavaScriptHandler(handlerName: 'symbols', callback: (_) => _symbols());
                    c.addJavaScriptHandler(handlerName: 'toggleBp', callback: (a) => s.toggleBreakpoint(a[0], _i(a[1])));
                    c.addJavaScriptHandler(handlerName: 'bpsChanged', callback: (a) => s.bpsChangedFromEditor(a[0], [for (final x in (a[1] as List)) _i(x)]));
                    c.addJavaScriptHandler(handlerName: 'dbg', callback: (a) => s.debugKey('${a[0]}'));
                    c.addJavaScriptHandler(handlerName: 'zoom', callback: (a) => s.zoom(_i(a[0])));
                    c.addJavaScriptHandler(handlerName: 'lens', callback: (a) => s.lens('${a[0]}', a[1] as String, '${a[2]}'));
                  },
                ),
      );
    }
    return _wv!;
  }

  /// Editor de respaldo (Linux): sin resaltado, pero funcional, mientras el WebView no esté disponible.
  Widget _plainEditor(t) {
    final d = s.current;
    if (d == null || d.isImage) return const SizedBox.shrink();
    final c = _plainCtl.putIfAbsent(d.path, () => TextEditingController(text: d.content));
    return Container(
      color: t.bg,
      child: TextField(
        key: ValueKey(d.path),
        controller: c,
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(fontFamily: 'monospace', fontSize: s.fontSize, color: t.text, height: 1.35),
        decoration: const InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, contentPadding: EdgeInsets.all(12)),
        onChanged: (v) => s.onEdit(d.path, v),
      ),
    );
  }

  Widget _welcome(BuildContext context, t) => Container(
        color: t.bg,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const LogoMark(size: 128, background: true),
          const SizedBox(height: 12),
          const Text(kAppName, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: .5)),
          const SizedBox(height: 4),
          Text(s.root == null ? 'Crea o abre un proyecto para empezar' : 'Abre un archivo desde el explorador', style: TextStyle(color: t.muted)),
          if (s.root == null) ...[
            const SizedBox(height: 20),
            Row(mainAxisSize: MainAxisSize.min, children: [
              FilledButton.icon(onPressed: () => showCreateProject(context, s), icon: const Icon(Icons.add), label: const Text('Nuevo proyecto')),
              const SizedBox(width: 10),
              OutlinedButton.icon(onPressed: () => pickAndOpenFolder(s), icon: const Icon(Icons.folder_open), label: const Text('Abrir carpeta')),
            ]),
          ],
        ]),
      );
}
