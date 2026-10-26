#!/usr/bin/env python3
"""HTTPS-only fixture server with byte ranges and an explicit cookie-gated test route."""
import argparse
import json
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import mimetypes
from pathlib import Path
import re
import ssl
import time
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]/'Fixtures/generated'
mimetypes.add_type('application/vnd.apple.mpegurl', '.m3u8')
mimetypes.add_type('video/mp2t', '.ts')

class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        # Negotiate TLS in this worker, never inside the listener's accept().
        # Bound idle preconnects while allowing unrelated requests to proceed.
        self.connection.settimeout(15)
    def log_message(self, format, *args): pass # Do not log query strings or cookie values.
    def do_HEAD(self): self.respond_safely(head=True)
    def do_GET(self): self.respond_safely(head=False)
    def do_POST(self):
        # The read-only client must never send account writes or credentials.
        size = int(self.headers.get('Content-Length', '0'))
        if size != 2 or self.rfile.read(size) != b'{}': self.send_error(400); return
        if '/library' not in urlsplit(self.path).path: self.send_error(405); return
        self.respond_safely(head=False)

    def respond_safely(self, head):
        try: self.respond(head)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLEOFError): pass # Expected when a playback test cancels a request.

    def respond(self, head):
        path = unquote(urlsplit(self.path).path)
        if path == '/metadata-transient.mp4':
            if self.headers.get('Range') == 'bytes=0-262143' and not getattr(self.server, 'metadata_dropped_once', False):
                self.server.metadata_dropped_once = True
                self.send_response(206)
                self.send_header('Content-Type', 'video/mp4')
                self.send_header('Content-Range', 'bytes 0-262143/1048576')
                self.send_header('Content-Length', '262144'); self.end_headers()
                self.wfile.write(b'partial'); self.wfile.flush()
                self.close_connection = True
                return
            path = '/opaque-b.mp4'
        if path in {'/download-redirect.mp4', '/download-foreign.mp4', '/download-insecure.mp4', '/download-public-redirect.mp4'}:
            self.send_response(302)
            target = '/vr180-sbs.mp4' if path == '/download-redirect.mp4' else f'https://localhost:{self.server.server_port}/vr180-sbs.mp4'
            if path == '/download-insecure.mp4': target = f'http://localhost:{self.server.server_port}/vr180-sbs.mp4'
            if path == '/download-public-redirect.mp4': target = f'https://localhost:{self.server.server_port}/download-public-check.mp4'
            self.send_header('Location', target); self.send_header('Content-Length', '0'); self.end_headers()
            return
        if path == '/dimensions-route.mp4':
            if head:
                self.send_response(200); self.send_header('Content-Length', '0'); self.end_headers(); return
            self.send_response(302); self.send_header('Location', f'https://localhost:{self.server.server_port}/dimensions-high.mp4?fixture=published%2Buri'); self.send_header('Content-Length', '0'); self.end_headers(); return
        if path == '/dimensions-low.mp4': path = '/vr180-mono.mp4'
        if path == '/dimensions-high.mp4': path = '/vr360-sbs.mp4'
        if path == '/download-invalid-mp4.mp4':
            body = b'<html>Fixture error response, not a video</html>'
            self.send_response(200); self.send_header('Content-Type', 'video/mp4'); self.send_header('Content-Length', str(len(body))); self.end_headers()
            if not head: self.wfile.write(body)
            return
        if path == '/download-public-check.mp4':
            if any(self.headers.get(name) for name in ['Cookie', 'Authorization', 'Origin', 'Referer', 'X-Private-Test']) or self.headers.get('User-Agent') != 'VisionStream-public-redirect-test':
                self.send_error(403); return
            path = '/vr180-sbs.mp4'
        if path == '/download-slow.mp4':
            body = (ROOT/'controls-demo.mp4').read_bytes()
            self.send_response(200); self.send_header('Content-Type', 'video/mp4')
            self.send_header('Content-Length', str(len(body))); self.end_headers()
            if not head:
                for offset in range(0, len(body), 4096):
                    self.wfile.write(body[offset:offset+4096]); self.wfile.flush(); time.sleep(0.05)
            return
        if path in {'/automation-mp4', '/automation-hls'}:
            source = '/controls-demo.mp4' if path == '/automation-mp4' else '/hls/controls-demo/master.m3u8'
            body = f'''<!doctype html><title>CC0 automated playback check</title>
<style>body{{font:24px system-ui;color:white;background:#18202a}}video{{width:75%}}</style>
<h1>CC0 calibration stream</h1><p>32 seconds, looping webpage playback; native playback uses the original stream.</p>
<video id="video" autoplay muted loop playsinline controls src="{source}"></video>'''.encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body))); self.end_headers()
            if not head: self.wfile.write(body)
            return
        if path == '/agent-context-test':
            # Test-server memory only. Compare the native client with the actual
            # WebKit request identifier without logging or returning its value.
            self.server.fixture_browser_user_agent = self.headers.get('User-Agent')
            body = b'<!doctype html><title>Browser request context fixture</title><p>Request context registered.</p>'
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body))); self.end_headers()
            if not head: self.wfile.write(body)
            return
        if path == '/agent-observations':
            body=json.dumps(getattr(self.server,'fixture_agent_observations',[])).encode()
            self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers()
            if not head:self.wfile.write(body)
            return
        if path.startswith('/agent-test/'):
            expected = getattr(self.server, 'fixture_browser_user_agent', None)
            observations=getattr(self.server,'fixture_agent_observations',[])
            observations.append({'segment':path.endswith('.ts'),'present':self.headers.get('User-Agent') is not None,'matches':self.headers.get('User-Agent')==expected})
            self.server.fixture_agent_observations=observations[-64:]
            if not expected or self.headers.get('User-Agent') != expected:
                self.send_error(403, 'Browser request identifier mismatch.'); return
            path = path[len('/agent-test'):]
        if path in {'/web-delayed-playback-test', '/web-delayed-hls-playback-test'}:
            # An unmuted, audible-track video started by the page after asynchronous
            # setup, without an injected JavaScript user gesture. Result names are
            # fixed; no exception messages or source URLs enter the test output.
            body = b'''<!doctype html><title>Delayed website playback fixture</title>
<video id="video" playsinline controls preload="none" src="/vr180-sbs.mp4"></video>
<script>
window.fixtureResult = 'pending';
setTimeout(() => {
  const video = document.querySelector('video');
  video.volume = 0.01;
  video.play().then(() => { window.fixtureResult = 'started'; }, error => {
    window.fixtureResult = error.name === 'NotAllowedError' ? 'gesture-required' : 'other-rejection';
  });
}, 300);
</script>'''
            if path == '/web-delayed-hls-playback-test':
                body = body.replace(b'/vr180-sbs.mp4', b'/hls/vr180-sbs/master.m3u8')
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body))); self.end_headers()
            if not head: self.wfile.write(body)
            return
        if path.startswith('/header-free/'):
            # Prove the native fallback can decode manifests and segments without
            # an extractor's custom request context being injected.
            if any(name in self.headers for name in ['Origin', 'Referer', 'Authorization', 'Cookie']):
                self.send_error(403, 'Unexpected website request header.'); return
            path = path[len('/header-free'):]
        if path in {'/metadata-ignore-range.mp4', '/metadata-oversize'}:
            body = (ROOT/'opaque-b.mp4').read_bytes()
            self.send_response(200 if path.endswith('.mp4') else 206)
            self.send_header('Content-Type', 'video/mp4')
            if path.endswith('oversize'): self.send_header('Content-Range', 'bytes 0-524287/1048576')
            self.send_header('Content-Length', str(len(body))); self.end_headers()
            if not head: self.wfile.write(body)
            return
        if path.startswith('/quality-cookie/'):
            cookies = SimpleCookie()
            try: cookies.load(self.headers.get('Cookie', ''))
            except Exception: pass
            if cookies.get('quality_browser') is None or cookies['quality_browser'].value != 'allowed':
                self.send_error(401); return
            if path == '/quality-cookie/master.m3u8':
                body = b'#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1440x720,CODECS="avc1.640020,mp4a.40.2"\nhigh/index.m3u8\n'
                self.send_response(200)
                self.send_header('Content-Type', 'application/vnd.apple.mpegurl')
                self.send_header('Set-Cookie', 'quality_issued=allowed; Path=/quality-cookie/high/; Secure; HttpOnly')
                self.send_header('Content-Length', str(len(body))); self.end_headers()
                if not head: self.wfile.write(body)
                return
            if cookies.get('quality_issued') is None or cookies['quality_issued'].value != 'allowed':
                self.send_error(401); return
            path = path.replace('/quality-cookie/high/', '/quality/high/', 1)
        if path == '/adaptive-test/master.m3u8':
            body = b'#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1024x512,CODECS="avc1.64001f,mp4a.40.2"\n/header-free/hls/vr360-mono/master.m3u8\n'
            self.send_response(200)
            self.send_header('Content-Type', 'application/vnd.apple.mpegurl')
            self.send_header('Content-Length', str(len(body))); self.end_headers()
            if not head: self.wfile.write(body)
            return
        if path in {'/cross-origin-test', '/frame-test', '/empty-test', '/web-playback-test', '/web-hls-playback-test', '/web-error-test', '/web-public-playback-test'}:
            if path in {'/web-playback-test', '/web-hls-playback-test', '/web-error-test', '/web-public-playback-test'}:
                source = {'/web-playback-test':'/vr180-sbs.mp4', '/web-hls-playback-test':'/hls/vr180-sbs/master.m3u8',
                          '/web-error-test':'/missing-test.mp4',
                          '/web-public-playback-test':'https://svs.gsfc.nasa.gov/vis/a010000/a014500/a014576/14576_BHPlunge_360_FINAL_1080.mp4'}[path]
                body = f'<!doctype html><title>Web playback fixture</title><video id="video" muted playsinline controls src="{source}"></video>'.encode()
            elif path == '/cross-origin-test':
                # localhost and 127.0.0.1 are distinct origins; the test certificate covers both.
                body = f'<!doctype html><title>Cross-origin fixture</title><video src="/vr180-sbs.mp4"></video><iframe src="https://localhost:{self.server.server_port}/frame-test"></iframe>'.encode()
            elif path == '/frame-test':
                body = b'<!doctype html><title>Frame fixture</title><video src="/vr360-tb.mp4"></video><div id="shadow"></div><script>document.querySelector("#shadow").attachShadow({mode:"open"}).innerHTML=\'<video src="/vr360-mono.mp4"></video>\';</script>'
            else:
                body = b'<!doctype html><title>No videos</title><p>Navigation fixture without media.</p>'
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body))); self.end_headers()
            if not head: self.wfile.write(body)
            return
        if path.startswith('/delayed/'):
            # A controlled slow response makes cancellation races reproducible in native tests.
            time.sleep(1)
            path = path[len('/delayed'):]
        if path == '/auth-test':
            body = b'<!doctype html><title>Cookie fixture</title><h1>Same-host cookie playback</h1><p>The server has set a Secure HttpOnly cookie scoped to /auth/. Native MP4 and HLS playback should retain it.</p><video controls playsinline width="500" src="/auth/vr180-sbs.mp4"></video><video controls playsinline width="500"><source src="/auth/hls/vr180-sbs/master.m3u8" type="application/vnd.apple.mpegurl"></video>'
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Set-Cookie', 'visionstream_fixture=authorised; Path=/auth/; Secure; HttpOnly; SameSite=Strict')
            self.send_header('Content-Length', str(len(body))); self.end_headers()
            if not head: self.wfile.write(body)
            return
        if path.startswith('/auth/'):
            cookies = SimpleCookie()
            try: cookies.load(self.headers.get('Cookie', ''))
            except Exception: pass
            value = cookies.get('visionstream_fixture')
            if not value or value.value != 'authorised': self.send_error(401, 'Open /auth-test first.'); return
            path = path[len('/auth'):]
        if path.startswith('/broken-hls/'):
            if path.endswith('/segment-008.ts'):
                self.send_error(404);return
            path=path.replace('/broken-hls/','/hls/controls-demo/',1)
        if path.startswith('/resource-trace/'):
            counts=getattr(self.server,'resource_trace_counts',{})
            self.server.resource_trace_counts=counts
            counts[path]=counts.get(path,0)+1
            if path == '/resource-trace/status':
                body=json.dumps({'keyRequests':counts.get('/resource-trace/private-key',0),
                                 'redirectTargetRequests':counts.get('/resource-trace/redirect-target',0)}).encode()
                mime='application/json'
            elif path == '/resource-trace/redirect.m3u8':
                self.send_response(302);self.send_header('Location','/resource-trace/redirect-target');self.send_header('Content-Length','0');self.end_headers();return
            elif path == '/resource-trace/master.m3u8':
                body=b'#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1024x512,CODECS="avc1.64001f,mp4a.40.2"\nvideo.m3u8?published=exact%2Bquery\n'
                mime='application/vnd.apple.mpegurl'
            elif path == '/resource-trace/video.m3u8':
                body=b'#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:731\n#EXT-X-KEY:METHOD=AES-128,URI="private-key"\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:4,\ngood.ts\n#EXTINF:4,\nmissing.ts?published=exact%2Bquery\n#EXTINF:4,\nlast.ts\n#EXT-X-ENDLIST\n'
                mime='application/vnd.apple.mpegurl'
            elif path in {'/resource-trace/init.mp4','/resource-trace/good.ts','/resource-trace/last.ts'}:
                # Header-only diagnostic cancellation must not wait for or copy a media body.
                self.send_response(206);self.send_header('Content-Type','video/mp2t');self.send_header('Content-Length','2');self.send_header('Content-Range','bytes 0-1/100000000');self.end_headers()
                if not head:self.wfile.write(b'AB')
                return
            else:
                self.send_error(404);return
            self.send_response(200);self.send_header('Content-Type',mime);self.send_header('Content-Length',str(len(body)));self.end_headers()
            if not head:self.wfile.write(body)
            return
        if path.startswith('/library'):
            prefix = '/auth' if unquote(urlsplit(self.path).path).startswith('/auth/') else ''
            if path in {'/library/no-cookie', '/library/set-cookie'} and self.headers.get('Cookie'):
                self.send_error(403, 'Unexpected cookie outside its scope.'); return
            if path == '/library/redirect':
                self.send_response(302)
                self.send_header('Location', '/library/no-cookie')
                self.send_header('Content-Length', '0'); self.end_headers(); return
            if path == '/library/forbidden': self.send_error(403); return
            if path == '/library/post-only' and self.command != 'POST': self.send_error(405); return
            if path == '/library/denied': payload = {'access': -1, 'library': []}
            elif path == '/library/invalid': payload = {'unknown': 'not a library'}
            elif path == '/library/huge': payload = {'access': 1, 'library': [], 'padding': 'x' * 2_097_153}
            elif path == '/library/oversize-chunked':
                # No declared length: exercise the client's streaming byte limit too.
                self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
                if not head:
                    for _ in range(129): self.wfile.write(b' ' * 16384)
                return
            elif path == '/library' or path == '/library/':
                payload = {'access': 1 if prefix else 0, 'library': [{'name': 'CC0 calibration', 'list': [prefix + '/library/' + name for name in ['vr180-mono','vr180-sbs','vr180-tb','vr360-mono','vr360-sbs','vr360-tb']]}]}
            else:
                name = path.rsplit('/', 1)[-1]
                if name in {'no-cookie', 'set-cookie', 'post-only'}: name = 'vr180-sbs'
                if name not in {'vr180-mono','vr180-sbs','vr180-tb','vr360-mono','vr360-sbs','vr360-tb'}:
                    self.send_error(404); return
                projection, stereo = name.split('-')
                payload = {'access': 1 if prefix else 0, 'title': 'Original CC0 ' + name, 'projection': 'equirectangular',
                           'fov': 180 if projection == 'vr180' else 360, 'stereo': stereo,
                           'media': [{'name':'MP4', 'sources':[{'resolution':512, 'url':prefix + '/' + name + '.mp4'}]},
                                     {'name':'HLS', 'sources':[{'resolution':'512', 'url':prefix + '/hls/' + name + '/master.m3u8'}]}]}
            body = json.dumps(payload).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('HereSphere-JSON-Version', '1')
            self.send_header('Cache-Control', 'no-store')
            if path == '/library/set-cookie':
                self.send_header('Set-Cookie', 'visionstream_library_ignored=must-not-persist; Path=/; Secure; HttpOnly')
            self.send_header('Content-Length', str(len(body))); self.end_headers()
            if not head: self.wfile.write(body)
            return
        local_media = getattr(self.server, 'local_media_file', None)
        if path == '/local-user-media.mp4' and local_media is not None:
            # Opt-in loopback test route only; no arbitrary URL-to-file mapping.
            file = local_media
        else:
            file = (ROOT/path.lstrip('/')).resolve()
            if not file.is_relative_to(ROOT.resolve()): self.send_error(403); return
        if file.is_dir(): file = file/'index.html'
        if not file.is_file(): self.send_error(404); return
        size = file.stat().st_size
        start, end, partial = 0, size - 1, False
        header = self.headers.get('Range')
        if header:
            match = re.fullmatch(r'bytes=(\d*)-(\d*)', header)
            try:
                if not match or not any(match.groups()): raise ValueError()
                first, last = match.groups()
                if first: start, end = int(first), min(int(last) if last else size - 1, size - 1)
                else: start, end = max(0, size - int(last)), size - 1
                if start > end or start >= size or int(last or '1') == 0 and not first: raise ValueError()
                partial = True
            except ValueError:
                self.send_response(416); self.send_header('Content-Range', f'bytes */{size}'); self.end_headers(); return
        self.send_response(206 if partial else 200)
        self.send_header('Content-Type', mimetypes.guess_type(file.name)[0] or 'application/octet-stream')
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(end - start + 1))
        if partial: self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.end_headers()
        if not head:
            with file.open('rb') as stream:
                stream.seek(start)
                remaining = end - start + 1
                while remaining > 0:
                    chunk = stream.read(min(64 * 1024, remaining))
                    if not chunk: break
                    self.wfile.write(chunk); remaining -= len(chunk)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cert', required=True)
    parser.add_argument('--key', required=True)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8443)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(args.cert, args.key)
    server.socket = context.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
    print(f'Serving CC0 fixtures over HTTPS on {args.host}:{args.port}; use a certificate trusted by the client.')
    server.serve_forever()

if __name__ == '__main__': main()
