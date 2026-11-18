/// Página HTML del editor de diferencias de Monaco (lado a lado o en línea).
String diffHtml(String src, String bg) => _tpl.replaceAll('__SRC__', src).replaceAll('__BG__', bg);

const _tpl = r'''<html><head><style>html,body,#c{margin:0;height:100%;background:__BG__}</style></head><body><div id="c"></div>
<script src="__SRC__/loader.js"></script>
<script>
require.config({paths:{vs:'__SRC__'}});
require(['vs/editor/editor.main'],()=>{
  const ed=monaco.editor.createDiffEditor(document.getElementById('c'),{theme:'vs-dark',automaticLayout:true,renderSideBySide:true,readOnly:true,originalEditable:false,minimap:{enabled:false},scrollBeyondLastLine:false,renderOverviewRuler:true,ignoreTrimWhitespace:false});
  let o=null,m=null;
  window.setDiff=(a,b,l)=>{const no=monaco.editor.createModel(a,l),nm=monaco.editor.createModel(b,l);ed.setModel({original:no,modified:nm});if(o)o.dispose();if(m)m.dispose();o=no;m=nm;};
  window.setSide=v=>ed.updateOptions({renderSideBySide:v});
  window.applyTheme=(def,id,fs)=>{monaco.editor.defineTheme(id,def);monaco.editor.setTheme(id);ed.updateOptions({fontSize:fs});document.body.style.background=def.colors['editor.background'];};
  window.flutter_inappwebview.callHandler('ready');
});
</script></body></html>''';
