// Unit tests for the shipped isolated-world script. Trusted event objects are
// modelled here; native WebKit tests separately prove synthetic clicks fail.
const assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../VisionStream/Resources/VideoDetector.js'),'utf8');
function fixture() {
  let now=1000,serial=0;
  const listeners={},windowListeners={},reports=[];
  class Element {
    constructor(kind='div') { this.events={};this.kind=kind;this.tagName=kind.toUpperCase();this.textContent='';this.hidden=false;this.ad=false;this.rect={left:0,top:0,right:640,bottom:360,width:640,height:360}; }
    closest(selector) {
      if (this.kind==='input' && selector.includes('textarea')) return this;
      if (this.ad && selector.includes('data-ad-slot')) return this;
      if (this.kind==='button' && selector.startsWith('button')) return this;
      if (this.player && selector.includes('data-player')) return this.player;
      return null;
    }
    contains(node) { return node===this; }
    getBoundingClientRect() { return this.rect; }
    getAttribute(name) { return name==='src' ? this.src : name==='type' ? 'video/mp4' : null; }
    querySelectorAll() { return []; }
    addEventListener(name,action) { (this.events[name] ||= []).push(action); }
    emit(name) { for (const action of this.events[name] || []) action({type:name}); }
  }
  const video=new Element('video');Object.assign(video,{src:'https://media.example/video.mp4',currentSrc:'https://media.example/video.mp4',paused:true,ended:false,readyState:4,networkState:2,videoWidth:1440,videoHeight:720,currentTime:0,duration:30,muted:false,buffered:{length:1,start:()=>0,end:()=>5},seekable:{length:1,start:()=>0,end:()=>30},style:{display:'block',visibility:'visible',opacity:'1'}});
  video.pause=()=>{video.paused=true};
  const body=new Element('body'),overlay=new Element('button');
  const document={title:'Fixture',body,readyState:'complete',visibilityState:'visible',querySelectorAll:selector=>selector==='video' ? [video] : [],addEventListener:(name,action)=>{listeners[name]=action}};
  const context=vm.createContext({Element,document,location:{href:'https://page.example/video'},innerWidth:1024,innerHeight:768,getComputedStyle:v=>v.style,
    crypto:{randomUUID:()=>`00000000-0000-4000-8000-${String(++serial).padStart(12,'0')}`},navigator:{userAgent:'Diagnostic fixture'},performance:{now:()=>now,timeOrigin:1700000000000,getEntriesByType:()=>[]},MutationObserver:class { observe(){} },
    setInterval:()=>1,setTimeout:()=>1,webkit:{messageHandlers:{visionStream:{postMessage:message=>reports.push(message)}}}});
  context.window=context;context.addEventListener=(name,action)=>{windowListeners[name]=action};
  vm.runInContext(source,context);
  function event(type='click',values={}) { const target=values.target||overlay;listeners[type]({type,isTrusted:true,repeat:false,clientX:100,clientY:100,key:' ',target,composedPath:()=>[target,body],...values}); }
  return {Element,context,video,document,body,overlay,diagnostics:()=>context.visionStreamDetector.diagnostics(),error:values=>windowListeners.error(values),input:new Element('input'),event,reports,scan:()=>context.visionStreamDetector.scan()[0],advance:ms=>{now+=ms;}};
}
let passed=0;
function test(name,run) { run();passed++;process.stdout.write('PASS '+name+'\n'); }
test('programmatic autoplay has no intent',()=>{const f=fixture();f.video.paused=false;assert.equal(f.scan().playIntent,null);});
test('synthetic click cannot authorize handoff',()=>{const f=fixture();f.event('click',{isTrusted:false});f.video.paused=false;assert.equal(f.scan().playIntent,null);});
test('trusted overlay play authorizes the actual video and waits for playback',()=>{const f=fixture();f.event();let c=f.scan();assert.ok(c.playIntent);assert.equal(c.webMedia.paused,true);f.video.paused=false;c=f.scan();assert.equal(c.webMedia.paused,false);assert.equal(c.playIntent.visible,true);});
test('pointerdown and click share one activation',()=>{const f=fixture();f.event('pointerdown');const id=f.scan().playIntent.id;f.advance(100);f.event('click');assert.equal(f.scan().playIntent.id,id);});
test('later intentional play gets a fresh activation',()=>{const f=fixture();f.event();const id=f.scan().playIntent.id;f.advance(1000);f.event();assert.notEqual(f.scan().playIntent.id,id);});
test('background and unrelated page clicks do not launch',()=>{const f=fixture();f.document.visibilityState='hidden';f.event();assert.equal(f.scan().playIntent,null);f.document.visibilityState='visible';f.event('click',{clientX:900,clientY:700,target:f.body});assert.equal(f.scan().playIntent,null);});
test('hidden offscreen and tiny players are excluded',()=>{for (const mutate of [v=>{v.hidden=true},v=>{v.style.opacity='0'},v=>{v.rect.left=2000;v.rect.right=2640},v=>{v.rect.width=40}]) { const f=fixture();mutate(f.video);f.event();assert.equal(f.scan().playIntent,null); }});
test('explicit advert markers suppress opening',()=>{const f=fixture();f.video.ad=true;f.event();assert.equal(f.scan().playIntent,null);});
test('editing fields and key repeat are not play gestures',()=>{const f=fixture();f.event('keydown',{repeat:true,target:f.body});assert.equal(f.scan().playIntent,null);f.event('keydown',{target:f.input});assert.equal(f.scan().playIntent,null);});
test('keyboard play on the focused video works',()=>{const f=fixture();f.event('keydown',{target:f.video});assert.ok(f.scan().playIntent);});
test('space for scrolling a page is not a play gesture',()=>{const f=fixture();f.event('keydown',{target:f.body});assert.equal(f.scan().playIntent,null);});
test('explicit player button can arm a hidden poster video, but visibility must follow',()=>{const f=fixture();f.overlay.player={contains:v=>v===f.video};f.video.style.opacity='0';f.event();assert.equal(f.scan().playIntent.visible,false);f.video.style.opacity='1';f.video.paused=false;assert.equal(f.scan().playIntent.visible,true);});
test('stale gestures expire',()=>{const f=fixture();f.event();assert.ok(f.scan().playIntent);f.advance(30001);assert.equal(f.scan().playIntent,null);});
test('clicking an already playing video does not claim a new play',()=>{const f=fixture();f.video.paused=false;f.event();assert.equal(f.scan().playIntent,null);});
test('diagnostic observations are bounded and do not alter playback',()=>{
  const f=fixture(),source=f.video.currentSrc;f.video.paused=false;f.video.currentTime=7;
  for(let i=0;i<40;i++){f.advance(10);f.video.emit('waiting');}
  for(let i=0;i<20;i++)f.error({error:{name:'TypeError'},message:'PRIVATE_ERROR_CONTENT',filename:'https://page.example/player.js',lineno:i,colno:2});
  const state=f.diagnostics(),v=state.videos[0];
  assert.equal(state.readyState,'complete');assert.equal(state.userAgent,'Diagnostic fixture');
  assert.equal(v.currentTime,7);assert.equal(v.paused,false);assert.equal(v.events.length,32);
  assert.equal(v.buffered[0][1],5);assert.equal(v.seekable[0][1],30);assert.equal(state.scriptErrors.length,16);
  assert.equal(state.scriptErrors[0].name,'TypeError');assert.ok(state.observedAtMs>1700000000000);
  assert.equal(JSON.stringify(state).includes('PRIVATE_ERROR_CONTENT'),false);
  assert.equal(f.video.currentSrc,source);assert.equal(f.video.paused,false);assert.equal(f.video.currentTime,7);
});
test('hidden texture video associates only a single visible canvas inside its player',()=>{
  const f=fixture(),canvas=new f.Element('canvas');canvas.style={display:'block',visibility:'visible',opacity:'1'};
  const player={querySelectorAll:q=>q==='video'?[f.video]:q==='canvas'?[canvas]:[],contains:n=>[f.video,canvas,f.overlay].includes(n)};
  f.video.player=player;f.overlay.player=player;f.video.hidden=true;
  f.video.currentSrc='blob:https://page.example/local';f.event();f.video.paused=false;
  const media=f.scan();assert.equal(media.webMedia.canvasBacked,true);assert.equal(media.playIntent.visible,true);
  assert.equal(media.source,'blob:https://page.example/local');assert.equal(media.webMedia.adMarked,false);
  f.video.mediaKeys={};assert.equal(f.scan().encrypted,true);
});
test('detached decoder requires visible VR canvas and a media request; never invents autoplay or a stream',()=>{
  const f=fixture(),canvas=new f.Element('canvas'),button=new f.Element('button');
  canvas.style=button.style={display:'block',visibility:'visible',opacity:'1'};button.textContent='Enter VR';
  button.rect={left:4,top:4,right:36,bottom:36,width:32,height:32};
  f.document.querySelectorAll=q=>q==='canvas'?[canvas]:q.startsWith('button')?[button]:[];
  assert.equal(f.scan(),undefined);
  f.context.URL=URL;f.context.performance.getEntriesByType=()=>[{name:'https://media.example/scene.m3u8',initiatorType:'fetch'}];
  const media=f.scan();assert.equal(media.source,'');assert.equal(media.webMedia.canvasBacked,true);assert.equal(media.playIntent,null);assert.equal(media.webMedia.readyState,0);
  button.textContent='Privacy';assert.equal(f.scan(),undefined);
  button.textContent='VR';button.hidden=true;assert.equal(f.scan(),undefined);
  button.hidden=false;button.rect.width=0;assert.equal(f.scan(),undefined);
});
test('an unrelated advert video does not hide detached XR source discovery',()=>{
  const f=fixture(),canvas=new f.Element('canvas'),button=new f.Element('button');
  canvas.style=button.style={display:'block',visibility:'visible',opacity:'1'};button.textContent='VR';f.video.ad=true;
  f.document.querySelectorAll=q=>q==='video'?[f.video]:q==='canvas'?[canvas]:q.startsWith('button')?[button]:[];
  f.context.URL=URL;f.context.performance.getEntriesByType=()=>[{name:'https://media.example/scene.mp4',initiatorType:'video'}];
  assert.equal(f.scan().source,'');assert.equal(f.scan().playIntent,null);
});
process.stdout.write(`${passed} detector unit tests; 0 failures\n`);
