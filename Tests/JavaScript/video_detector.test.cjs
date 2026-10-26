const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('VisionStream/Resources/VideoDetector.js', 'utf8');

function video(options = {}) {
  const sources = (options.sources || []).map(s => ({getAttribute(name){return this[name] ?? null;}, ...s}));
  return Object.assign({currentSrc:'',src:'',title:'',mediaKeys:null,videoWidth:2048,videoHeight:1024,currentTime:2,
    events:{}, paused:false, error:null, readyState:4, networkState:1, getAttribute(name){return this[name] || '';},
    querySelectorAll(){return sources;}, addEventListener(name, fn){this.events[name] = fn;},
    pause(){this.paused = true;}}, options);
}
function root(items, shadows = []) {
  return {title:'Fixture',querySelectorAll(query){return query === 'video' ? items : shadows.map(shadowRoot => ({shadowRoot}));}};
}
function harness(items, shadows = []) {
  let last;
  const context = vm.createContext({document:root(items,shadows),location:{href:'https://site.example/watch'},
    crypto:{randomUUID:()=> 'frame'},setInterval(){},setTimeout(){return 1;},
    MutationObserver:class{observe(){}},webkit:{messageHandlers:{visionStream:{postMessage(body){last = body;}}}}});
  vm.runInContext(source, context);
  return {context, scan:()=> context.visionStreamDetector.scan(), get last(){return last;}};
}

test('exposes actual MP4 currentSrc and decoder metadata', () => {
  const fixture = harness([video({currentSrc:'https://cdn.example/a.mp4',currentTime:42})]);
  assert.equal(fixture.last.candidates[0].source, 'https://cdn.example/a.mp4');
  assert.equal(fixture.last.candidates[0].currentTime, 42);
  assert.equal(fixture.last.candidates[0].width, 2048);
});
test('matches HLS MIME from source elements', () => {
  const fixture = harness([video({currentSrc:'https://cdn.example/master.m3u8', sources:[{src:'https://cdn.example/master.m3u8',type:'application/vnd.apple.mpegurl'}]})]);
  assert.equal(fixture.last.candidates[0].mimeType, 'application/vnd.apple.mpegurl');
});
test('blob playback suppresses stale direct source alternatives', () => {
  const fixture = harness([video({currentSrc:'blob:https://site.example/id', sources:[{src:'https://cdn.example/stale.mp4',type:'video/mp4'}]})]);
  assert.equal(fixture.last.candidates.length, 1);
  assert.equal(fixture.last.candidates[0].source, 'blob:https://site.example/id');
});
test('encrypted events and MediaKeys mark candidate as protected', () => {
  const item = video({src:'https://cdn.example/a.mp4'});
  const fixture = harness([item]);
  item.events.encrypted(); fixture.scan();
  assert.equal(fixture.last.candidates[0].encrypted, true);
  assert.equal(harness([video({src:item.src,mediaKeys:{}})]).last.candidates[0].encrypted, true);
});
test('finds open shadow root media and source-only elements', () => {
  const fixture = harness([], [root([video({sources:[{src:'https://cdn.example/a.mp4',type:'video/mp4'}]})])]);
  assert.equal(fixture.last.candidates.length, 1);
});
test('dynamic insertion, source changes and removal update reports', () => {
  const items = [];
  const fixture = harness(items);
  assert.equal(fixture.last.candidates.length, 0);
  const item = video({currentSrc:'https://cdn.example/old.mp4'});
  items.push(item); fixture.scan();
  const id = fixture.last.candidates[0].videoID;
  item.currentSrc = 'https://cdn.example/new.mp4'; fixture.scan();
  assert.equal(fixture.last.candidates[0].videoID, id);
  assert.equal(fixture.last.candidates[0].source, item.currentSrc);
  items.length = 0; fixture.scan();
  assert.equal(fixture.last.candidates.length, 0);
});
test('pauses only selected video when source still matches', () => {
  const a = video({currentSrc:'https://cdn.example/a.mp4'}), b = video({currentSrc:'https://cdn.example/b.mp4'});
  const fixture = harness([a,b]);
  const id = fixture.last.candidates[0].videoID;
  assert.equal(fixture.context.visionStreamDetector.pause(id, 'https://cdn.example/stale.mp4'), false);
  assert.equal(fixture.context.visionStreamDetector.pause(id, a.currentSrc), true);
  assert.equal(a.paused, true); assert.equal(b.paused, false);
});
test('bounds reports and sanitises nonfinite timestamps', () => {
  const fixture = harness(Array.from({length:40}, () => video({src:'https://cdn.example/a.mp4',currentTime:Infinity})));
  assert.equal(fixture.last.candidates.length, 16);
  assert.equal(fixture.last.candidates[0].currentTime, 0);
  assert.equal(harness([video({src:'https://cdn.example/'+'a'.repeat(17000)})]).last.candidates.length, 0);
});
test('installing twice does not replace the active detector', () => {
  const fixture = harness([]), initial = fixture.context.visionStreamDetector;
  vm.runInContext(source, fixture.context);
  assert.equal(fixture.context.visionStreamDetector, initial);
});

test('ignores empty source attributes whose DOM URL resolves to the webpage', () => {
  const page = 'https://site.example/watch';
  const empty = {src:page,type:'video/mp4',getAttribute:()=>''};
  const whitespace = {src:page,type:'application/vnd.apple.mpegurl',getAttribute:()=> '  '};
  const fixture = harness([
    video({src:page,getAttribute:()=>''}),
    video({src:page,getAttribute:()=> '  '}),
    video({sources:[empty,whitespace]})
  ]);
  assert.equal(fixture.last.candidates.length, 0);
});

test('reports webpage errors and states without reading error messages', () => {
  const item = video({src:'https://cdn.example/a.mp4',readyState:0,networkState:3,paused:true,
    error:{code:4,get message(){throw new Error('Must not read private error text');}}});
  const fixture = harness([item]);
  const state = fixture.last.candidates[0].webMedia;
  assert.equal(state.errorCode,4);
  assert.equal(state.readyState,0);
  assert.equal(state.networkState,3);
  assert.equal(state.paused,true);
  for (const event of ['error','waiting','stalled','pause']) assert.equal(typeof item.events[event],'function');
  item.error = null; item.readyState = 4; item.networkState = 1; item.paused = false;
  fixture.scan();
  assert.equal(fixture.last.candidates[0].webMedia.errorCode,0);
  assert.equal(fixture.last.candidates[0].webMedia.paused,false);
});
test('reads explicit projection and eye packing metadata without guessing from size', () => {
  const item = video({src:'https://cdn.example/a.mp4','data-projection':'equirectangular','data-fov':'180','data-stereo':'sbs'});
  let media = harness([item]).last.candidates[0];
  assert.equal(media.formatHint.projection, 'vr180');
  assert.equal(media.formatHint.layout, 'sideBySide');
  assert.equal(media.formatHint.evidence, 'metadata');
  assert.equal(harness([video({src:item.src,videoWidth:3840,videoHeight:1920})]).last.candidates[0].formatHint, null);
  item['data-projection'] = 'fisheye'; item['data-stereo'] = '';
  assert.equal(harness([item]).last.candidates[0].formatHint, null);
});
