"""Exercise the actual generated media and HTTPS server, never an external website."""
import importlib.util
import json
from pathlib import Path
import ssl
import socket
import time
import subprocess
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('fixture_server', ROOT/'Scripts/serve_fixtures.py')
server_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server_module)

class FixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='visionstream-tls-')
        cert = Path(cls.temp.name)/'cert.pem'; key = Path(cls.temp.name)/'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-sha256', '-nodes',
                        '-keyout', str(key), '-out', str(cert), '-days', '1', '-subj', '/CN=localhost',
                        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        cls.server = ThreadingHTTPServer(('127.0.0.1',0), server_module.Handler)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(cert,key)
        cls.server.socket = ctx.wrap_socket(cls.server.socket,server_side=True,do_handshake_on_connect=False)
        cls.context = ssl.create_default_context(cafile=str(cert))
        cls.origin = 'https://localhost:' + str(cls.server.server_port)
        cls.thread = threading.Thread(target=cls.server.serve_forever,daemon=True); cls.thread.start()
    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join(); cls.temp.cleanup()
    def request(self,path,**headers):
        return urlopen(Request(self.origin+path,headers=headers),context=self.context)

    def test_idle_tls_connection_cannot_block_other_fixture_requests(self):
        # Media frameworks may preconnect without sending a ClientHello yet.
        # That socket must not block the listener from accepting the next one.
        idle=socket.create_connection(('127.0.0.1',self.server.server_port),timeout=2)
        try:
            time.sleep(0.05)
            with urlopen(Request(self.origin+'/vr180-sbs.mp4',headers={'Range':'bytes=0-1'}),context=self.context,timeout=2) as response:
                self.assertEqual(response.status,206)
                self.assertEqual(len(response.read()),2)
        finally:
            idle.close()

    def test_quality_renditions_preserve_muxed_aac(self):
        for name, width, height in [('low', 480, 240), ('high', 1440, 720)]:
            segment = ROOT/'Fixtures/generated/quality'/name/'segment-000.ts'
            result = json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-of','json',str(segment)]))
            video = next(s for s in result['streams'] if s['codec_type'] == 'video')
            audio = next(s for s in result['streams'] if s['codec_type'] == 'audio')
            self.assertEqual((video['width'], video['height']), (width, height))
            self.assertEqual(audio['codec_name'], 'aac')
            with self.request('/quality/'+name+'/index.m3u8?fixture=published%2Buri') as response:
                self.assertEqual(response.status, 200)

    def test_native_4k_rendition_contains_expected_video_and_audio(self):
        segment = ROOT/'Fixtures/generated/quality-4k/segment-000.ts'
        data = json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-of','json',str(segment)]))
        video = next(s for s in data['streams'] if s['codec_type'] == 'video')
        self.assertEqual((video['width'], video['height']), (3840,1920))
        self.assertTrue(any(s['codec_name'] == 'aac' for s in data['streams']))
        with self.request('/quality-4k/master.m3u8') as response:
            text = response.read().decode()
        self.assertLess(text.index('480x240'), text.index('3840x1920'))

    def test_opaque_metadata_fixtures_decode_without_filename_hints(self):
        for name in ['opaque-a.mp4','opaque-b.mp4']:
            sample = ROOT/'Fixtures/generated'/name
            subprocess.run(['ffmpeg','-v','error','-i',str(sample),'-f','null','-'],check=True,capture_output=True)
            self.assertIn(bytes.fromhex('ffcc8263f8554a938814587a02521fdd'),sample.read_bytes())
            with self.request('/'+name,Range='bytes=0-262143') as response:
                self.assertEqual(response.status,206)
                self.assertTrue(response.headers['Content-Range'].startswith('bytes 0-'))

    def test_bad_metadata_range_routes_are_deliberate_http_responses(self):
        with self.request('/metadata-ignore-range.mp4',Range='bytes=0-262143') as response:
            self.assertEqual(response.status,200)
            self.assertGreater(len(response.read()),0)
        with self.request('/metadata-oversize',Range='bytes=0-262143') as response:
            self.assertEqual(response.status,206)
            self.assertEqual(response.headers['Content-Range'],'bytes 0-524287/1048576')

    def test_all_six_mp4_containers_and_dimensions(self):
        manifest = json.loads((ROOT/'Fixtures/generated/manifest.json').read_text())
        self.assertEqual(len(manifest),6)
        for item in manifest:
            result = subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(ROOT/'Fixtures/generated'/item['name'])])
            data = json.loads(result); video = next(s for s in data['streams'] if s['codec_type']=='video')
            self.assertEqual(video['codec_name'],'h264')
            self.assertAlmostEqual(float(data['format']['duration']),8,delta=0.1)
            base = (512,512) if item['projection']=='vr180' else (1024,512)
            expected = (base[0]*2,base[1]) if item['layout']=='sbs' else ((base[0],base[1]*2) if item['layout']=='tb' else base)
            self.assertEqual((video['width'],video['height']),expected)

    def test_mp4_byte_range_and_fast_start(self):
        with self.request('/vr180-sbs.mp4',Range='bytes=0-1023') as result:
            self.assertEqual(result.status,206)
            self.assertEqual(result.headers['Content-Type'],'video/mp4')
            self.assertIn('bytes 0-1023/',result.headers['Content-Range'])
            self.assertEqual(len(result.read()),1024)
        data = (ROOT/'Fixtures/generated/vr180-sbs.mp4').read_bytes()
        self.assertLess(data.index(b'moov'),data.index(b'mdat'))

    def test_web_playback_pages_use_the_real_https_media_routes(self):
        for page, source in [('/web-playback-test','/vr180-sbs.mp4'),
                             ('/web-hls-playback-test','/hls/vr180-sbs/master.m3u8')]:
            with self.request(page) as result:
                self.assertEqual(result.status,200)
                self.assertIn(f'src="{source}"'.encode(),result.read())
            with self.request(source) as result:
                self.assertEqual(result.status,200)

    def test_delayed_playback_fixture_preserves_the_real_page_gesture_boundary(self):
        for path, source in [('/web-delayed-playback-test', '/vr180-sbs.mp4'),
                             ('/web-delayed-hls-playback-test', '/hls/vr180-sbs/master.m3u8')]:
            with self.request(path) as response:
                body = response.read()
            self.assertIn(f'src="{source}"'.encode(), body)
            self.assertIn(b'setTimeout', body)
            self.assertIn(b'preload="none"', body)
            self.assertIn(b'NotAllowedError', body)
            self.assertNotIn(b' muted', body)

    def test_browser_identifier_gate_applies_to_manifest_and_segments(self):
        with self.request('/agent-context-test', **{'User-Agent':'VisionStream-Fixture'}): pass
        for path in ['/agent-test/vr180-sbs.mp4', '/agent-test/hls/vr180-sbs/master.m3u8',
                     '/agent-test/hls/vr180-sbs/segment-000.ts']:
            with self.assertRaises(HTTPError) as error:
                self.request(path)
            self.assertEqual(error.exception.code,403)
            error.exception.close()
        for path in ['/agent-test/vr180-sbs.mp4', '/agent-test/hls/vr180-sbs/master.m3u8']:
            with self.request(path, **{'User-Agent':'VisionStream-Fixture'}) as response:
                self.assertEqual(response.status,200)
                content=response.read()
            if path.endswith('.m3u8'):
                segment=next(line for line in content.decode().splitlines() if line and not line.startswith('#'))
                with self.request('/agent-test/hls/vr180-sbs/'+segment, **{'User-Agent':'VisionStream-Fixture'}) as response:
                    self.assertEqual(response.status,200)

    def test_private_local_sample_route_is_explicit_opt_in_and_supports_ranges(self):
        with self.assertRaises(HTTPError) as missing:
            self.request('/local-user-media.mp4')
        self.assertEqual(missing.exception.code,404)
        sample = Path(self.temp.name)/'private-sample.mp4'
        sample.write_bytes(b'0123456789')
        self.server.local_media_file = sample
        try:
            with self.request('/local-user-media.mp4',Range='bytes=2-5') as response:
                self.assertEqual(response.status,206)
                self.assertEqual(response.headers['Content-Type'],'video/mp4')
                self.assertEqual(response.read(),b'2345')
        finally:
            del self.server.local_media_file

    def test_automation_pages_and_seekable_hls(self):
        for page, source in [('/automation-mp4', '/controls-demo.mp4'),
                             ('/automation-hls', '/hls/controls-demo/master.m3u8')]:
            with self.request(page) as response:
                body = response.read()
                self.assertIn(f'src="{source}"'.encode(), body)
                self.assertIn(b'muted', body)
                self.assertIn(b'playsinline', body)
        with self.request('/hls/controls-demo/master.m3u8') as response:
            manifest = response.read().decode()
        self.assertIn('#EXT-X-ENDLIST', manifest)
        durations = [float(line.split(':')[1].rstrip(',')) for line in manifest.splitlines() if line.startswith('#EXTINF:')]
        self.assertAlmostEqual(sum(durations), 32, delta=0.25)
        for line in manifest.splitlines():
            if line and not line.startswith('#'):
                with self.request('/hls/controls-demo/'+line) as response:
                    self.assertEqual(response.status, 200)
                    self.assertGreater(len(response.read()), 0)

    def test_manual_controls_demo_duration_and_https_range(self):
        data = json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-of','json',str(ROOT/'Fixtures/generated/controls-demo.mp4')]))
        self.assertAlmostEqual(float(data['format']['duration']),32,delta=0.25)
        with self.request('/controls-demo.mp4',Range='bytes=0-31') as result:
            self.assertEqual(result.status,206)
            self.assertEqual(len(result.read()),32)
        with self.request('/controls.html') as result:
            self.assertIn(b'controls-demo.mp4',result.read())

    def test_hls_manifest_and_segments_over_https(self):
        manifest = json.loads((ROOT/'Fixtures/generated/manifest.json').read_text())
        for item in manifest:
            with self.request('/'+item['hls']) as result:
                self.assertEqual(result.headers['Content-Type'],'application/vnd.apple.mpegurl')
                playlist = result.read().decode()
            self.assertTrue(playlist.startswith('#EXTM3U'))
            self.assertIn('#EXT-X-ENDLIST',playlist)
            segments = [line for line in playlist.splitlines() if line and not line.startswith('#')]
            self.assertEqual(len(segments),4)
            for segment in segments:
                with self.request('/'+str(Path(item['hls']).parent/segment),Range='bytes=0-187') as result:
                    self.assertEqual(result.status,206)
                    self.assertEqual(result.read()[0],0x47)

    def test_adaptive_parent_references_a_working_media_playlist(self):
        with self.request('/header-free/adaptive-test/master.m3u8') as response:
            self.assertEqual(response.headers['Content-Type'], 'application/vnd.apple.mpegurl')
            content = response.read().decode()
        self.assertIn('#EXT-X-STREAM-INF:', content)
        child = next(line for line in content.splitlines() if line and not line.startswith('#'))
        with self.request(child) as response:
            self.assertIn(b'#EXTINF:', response.read())

    def test_cookie_gate_requires_explicit_fixture_session(self):
        with self.assertRaises(HTTPError) as error: self.request('/auth/vr180-sbs.mp4')
        self.assertEqual(error.exception.code,401)
        error.exception.close()
        with self.request('/auth-test') as response:
            self.assertIn('HttpOnly',response.headers['Set-Cookie'])
            cookie = response.headers['Set-Cookie'].split(';')[0]
        with self.request('/auth/vr180-sbs.mp4',Cookie=cookie,Range='bytes=0-31') as response:
            self.assertEqual(response.status,206)
        with self.request('/auth/hls/vr180-sbs/master.m3u8',Cookie=cookie) as response:
            self.assertTrue(response.read().startswith(b'#EXTM3U'))

    def test_header_free_route_rejects_custom_context_on_media_and_segments(self):
        paths = ['/header-free/vr360-mono.mp4', '/header-free/hls/vr360-mono/master.m3u8']
        with self.request(paths[1]) as response:
            segments = [line for line in response.read().decode().splitlines() if line and not line.startswith('#')]
        paths.append('/header-free/hls/vr360-mono/' + segments[0])
        for path in paths:
            with self.request(path, Range='bytes=0-15') as response:
                self.assertEqual(response.status, 206)
            for header in ['Origin', 'Referer', 'Authorization', 'Cookie']:
                with self.assertRaises(HTTPError) as error:
                    self.request(path, **{header: 'fixture-only'})
                self.assertEqual(error.exception.code, 403)
                error.exception.close()

    def test_invalid_ranges_and_traversal(self):
        for header in ['bytes=99999999-', 'bytes=-0', 'bytes=3-1', 'bytes=0-10,20-30']:
            with self.assertRaises(HTTPError) as error: self.request('/vr180-sbs.mp4',Range=header)
            self.assertEqual(error.exception.code,416)
            error.exception.close()
        with self.assertRaises(HTTPError) as error: self.request('/%2e%2e/secret')
        self.assertEqual(error.exception.code,403)
        error.exception.close()

    def test_read_only_library_and_video_metadata_match_media(self):
        with self.request('/library') as response:
            self.assertEqual(response.headers['Content-Type'], 'application/json')
            data = json.load(response)
        self.assertEqual(data['access'], 0)
        entries = data['library'][0]['list']
        self.assertEqual(len(entries), 6)
        for path in entries:
            with self.request(path) as response: detail = json.load(response)
            self.assertEqual(detail['projection'], 'equirectangular')
            self.assertEqual(detail['fov'], 180 if 'vr180' in path else 360)
            self.assertIn(detail['stereo'], {'mono','sbs','tb'})
            for media in detail['media']:
                with self.request(media['sources'][0]['url'], Range='bytes=0-15') as response:
                    self.assertEqual(response.status, 206)
        with self.assertRaises(HTTPError) as error: self.request('/auth/library')
        self.assertEqual(error.exception.code, 401)
        error.exception.close()
        with self.request('/auth-test') as response: cookie = response.headers['Set-Cookie'].split(';')[0]
        with self.request('/auth/library', Cookie=cookie) as response:
            data = json.load(response)
            self.assertEqual(data['access'], 1)
            self.assertTrue(all(p.startswith('/auth/') for p in data['library'][0]['list']))

if __name__=='__main__': unittest.main(verbosity=2)
