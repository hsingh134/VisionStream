#!/usr/bin/env python3
"""Run the built native tests against original CC0 fixtures in a dedicated simulator.

The temporary HTTPS certificate is trusted only inside the specified simulator.
The Mac's trust stores are never changed. Use a simulator created for this test workflow.
"""
import argparse
from datetime import datetime, timezone
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import plistlib
import ssl
import subprocess
import tempfile
import threading
import time
import uuid
from http.server import ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--simulator', required=True, help='UDID of a dedicated VisionStream test simulator')
    parser.add_argument('--output', type=Path, help='New directory for isolated logs, result bundle and metadata')
    parser.add_argument('--port', type=int, default=0)
    parser.add_argument('--build-root', type=Path, default=ROOT/'DerivedData', help='Derived data directory containing the built test bundle')
    parser.add_argument('--keep-serving', action='store_true', help='Keep the HTTPS fixtures running after tests for manual UI checks')
    parser.add_argument('--hls-offline-public-probe', action='store_true', help='Use the fixed Apple public HLS developer sample for the opt-in probe')
    parser.add_argument('--hls-offline-probe', action='store_true', help='Opt into the native HLS offline platform feasibility check')
    parser.add_argument('--public-extraction', action='store_true', help='Also resolve and render the public NASA HTTPS MP4 using the embedded extractor')
    parser.add_argument('--only-testing', action='append', default=[], help='Optional Xcode target/class/method filter for focused regression runs')
    parser.add_argument('--public-preview-input', type=Path, help='Explicit browser-observed preview URLs; held only in temporary test configuration, never in reports')
    parser.add_argument('--local-media', type=Path, help='Opt-in local MP4 under LocalMedia for a private loopback playback test; never packaged or logged')
    parser.add_argument('--local-vr180-sbs', action='store_true', help='Assert automatic VR180/SBS detection for the explicitly supplied known stereo sample')
    args = parser.parse_args()
    if args.local_vr180_sbs and not args.local_media:
        raise SystemExit('--local-vr180-sbs requires an explicitly supplied local MP4.')
    previews = None
    if args.public_preview_input:
        from urllib.parse import urlsplit
        if args.public_preview_input.stat().st_size > 65_536: raise SystemExit('Preview input is too large.')
        previews = json.loads(args.public_preview_input.read_text())
        hosts = {'vrBangers': 'mov.vrbangers.com', 'virtualReal': 'virtualrealporn.com', 'slr': 'cdn-vr.sexlikereal.com'}
        if not isinstance(previews, dict) or not previews or not previews.keys() <= hosts.keys(): raise SystemExit('Unsupported public preview source.')
        for site, values in previews.items():
            if not isinstance(values, list) or len(values) != 1 or not isinstance(values[0], dict) or set(values[0]) != {'source'} or not isinstance(values[0]['source'], str): raise SystemExit('Supply one observed source per supported site, without headers or cookies.')
            url = urlsplit(values[0]['source'])
            if url.scheme != 'https' or url.hostname != hosts[site] or url.username or url.password or url.fragment or len(values[0]['source']) > 16_384: raise SystemExit('Unsupported public preview URL.')
    output_directory = args.output or ROOT/'TestResults'
    if args.output: output_directory.mkdir(parents=True, exist_ok=False)
    if args.local_media:
        args.local_media = args.local_media.resolve()
        if not args.local_media.is_relative_to(ROOT/'LocalMedia') or not args.local_media.is_file() or args.local_media.suffix.lower() != '.mp4':
            raise SystemExit('The optional sample must be an MP4 file inside LocalMedia.')
    environment = dict(os.environ)
    environment.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
    inventory = subprocess.run(['xcrun', 'simctl', 'list', 'devices', '-j'], env=environment, check=True, capture_output=True, text=True)
    devices = json.loads(inventory.stdout)['devices']
    device = next((d for values in devices.values() for d in values if d['udid'] == args.simulator), None)
    if not device or not device['name'].startswith('VisionStream Automation Lab'):
        raise SystemExit('Use a dedicated VisionStream Automation Lab simulator; personal simulator sessions are not modified.')
    candidates = list((args.build_root/'Build/Products').glob('VisionStream_xrsimulator*.xctestrun'))
    if not candidates: raise SystemExit('Run xcodebuild build-for-testing for the VisionStream scheme first.')
    original = max(candidates, key=lambda p:p.stat().st_mtime)
    spec = importlib.util.spec_from_file_location('fixture_server', ROOT/'Scripts/serve_fixtures.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix='visionstream-simulator-tls-') as temporary:
        cert = Path(temporary)/'localhost.pem'; key = Path(temporary)/'localhost-key.pem'
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-sha256','-nodes',
                        '-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=VisionStream local test fixture',
                        '-addext','subjectAltName=DNS:localhost,IP:127.0.0.1',
                        '-addext','basicConstraints=critical,CA:TRUE'], check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        subprocess.run(['xcrun','simctl','keychain',args.simulator,'add-root-cert',str(cert)],env=environment,check=True)
        server = ThreadingHTTPServer(('127.0.0.1',args.port),module.Handler)
        server.local_media_file = args.local_media
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); context.load_cert_chain(cert,key)
        server.socket=context.wrap_socket(server.socket,server_side=True,do_handshake_on_connect=False)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        origin=f'https://127.0.0.1:{server.server_port}'
        data=plistlib.loads(original.read_bytes())
        targets=[]
        if 'TestConfigurations' in data:
            for configuration in data['TestConfigurations']: targets.extend(configuration.get('TestTargets',[]))
        else:
            targets=[value for name,value in data.items() if not name.startswith('__') and isinstance(value,dict)]
        for target in targets:
            target.setdefault('EnvironmentVariables',{})['VISIONSTREAM_TEST_ORIGIN']=origin
            if args.local_vr180_sbs:
                target['EnvironmentVariables']['VISIONSTREAM_TEST_LOCAL_VR180_SBS'] = '1'
            if previews is not None:
                target['EnvironmentVariables']['VISIONSTREAM_TEST_PUBLIC_PREVIEWS'] = json.dumps(previews)
            if args.hls_offline_public_probe:
                target['EnvironmentVariables']['VISIONSTREAM_TEST_HLS_PUBLIC_PROBE']='1'
            if args.hls_offline_probe:
                target['EnvironmentVariables']['VISIONSTREAM_TEST_HLS_OFFLINE_PROBE']='1'
            if args.public_extraction:
                target['EnvironmentVariables']['VISIONSTREAM_TEST_PUBLIC_EXTRACTOR']='1'
            if args.local_media:
                target['EnvironmentVariables']['VISIONSTREAM_TEST_LOCAL_MEDIA']='1'
        configured=original.with_name('VisionStream-HTTPS-'+uuid.uuid4().hex+'.xctestrun')
        configured.write_bytes(plistlib.dumps(data))
        stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
        result=output_directory/f'VisionStream-{stamp}.xcresult'
        log=output_directory/'visionos-native-tests.txt'
        host_hashes = {}
        for target in targets:
            host = Path(str(target.get('TestHostPath', '')).replace('__TESTROOT__', str(original.parent.resolve())))
            if host.is_dir() and (host/'Info.plist').is_file():
                host = host / plistlib.loads((host/'Info.plist').read_bytes()).get('CFBundleExecutable', 'VisionStream')
            if host.is_file(): host_hashes[host.name] = hashlib.sha256(host.read_bytes()).hexdigest()
        metadata={'testHostExecutableSHA256':host_hashes,'simulator':args.simulator,'origin':origin,'resultBundle':str(result),'log':str(log),
                  'localMediaIncluded':bool(args.local_media),'publicPreviewSites':sorted(previews or {}),'onlyTesting':args.only_testing}
        (output_directory/'native-test-session.json').write_text(json.dumps(metadata,indent=2)+'\n')
        print(f'Controlled HTTPS fixtures: {origin} (original CC0; any opt-in user sample is separate)',flush=True)
        print(f'Native test results: {result}',flush=True)
        try:
            with log.open('w') as output:
                completed=subprocess.run(['xcodebuild','test-without-building','-xctestrun',str(configured),
                    '-destination',f'platform=visionOS Simulator,id={args.simulator}',
                    '-parallel-testing-enabled','NO','-resultBundlePath',str(result)] +
                    [f'-only-testing:{value}' for value in args.only_testing],env=environment,stdout=output,stderr=subprocess.STDOUT,timeout=900)
            print(f'Native tests exited with status {completed.returncode}. See {log}.',flush=True)
            metadata['exitCode'] = completed.returncode
            report = subprocess.run(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],
                                    env=environment,capture_output=True,text=True)
            if report.returncode == 0:
                summary = json.loads(report.stdout)
                (output_directory/'visionos-native-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
                metadata['status'] = summary.get('result','Unknown')
                metadata['passedTests'] = summary.get('passedTests')
                metadata['failedTests'] = summary.get('failedTests')
                metadata['skippedTests'] = summary.get('skippedTests')
            (output_directory/'native-test-session.json').write_text(json.dumps(metadata,indent=2)+'\n')
            if args.keep_serving:
                print(f'HTTPS fixture server remains available at {origin}; stop this process after UI checks.',flush=True)
                while True: time.sleep(1)
            if completed.returncode: raise SystemExit(completed.returncode)
        except subprocess.TimeoutExpired:
            metadata.update(exitCode=124, status='TimedOut', failureReason='Native test runner exceeded its 15-minute deadline')
            (output_directory/'native-test-session.json').write_text(json.dumps(metadata,indent=2)+'\n')
            raise SystemExit('Native test runner exceeded its 15-minute deadline. See redacted logs.')
        finally:
            # Platform errors may print signed URLs independently of app diagnostics.
            if previews and log.exists():
                import re
                log.write_text(re.sub(r'https?://[^\s,}\)]+', '<URL omitted>', log.read_text()))
            server.shutdown();server.server_close();thread.join()
            configured.unlink(missing_ok=True)

if __name__=='__main__': main()
