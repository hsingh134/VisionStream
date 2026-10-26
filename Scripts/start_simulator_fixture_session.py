#!/usr/bin/env python3
"""Bounded, loopback-only CC0 fixture session for interactive simulator testing.

Only a dedicated VisionStream Automation Lab simulator may receive the temporary
test certificate. No Mac trust store, user simulator or website session is read.
Delete the dedicated simulator when finished to remove its test trust store.
"""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import signal
import ssl
import subprocess
import tempfile
import threading
from http.server import ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--metadata', type=Path, required=True)
    parser.add_argument('--lifetime', type=int, default=3600)
    args = parser.parse_args()
    if not 30 <= args.lifetime <= 7200:
        parser.error('Choose a lifetime between 30 seconds and two hours.')
    environment = dict(os.environ)
    environment['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'
    inventory = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '-j'], env=environment))
    device = next((d for devices in inventory['devices'].values() for d in devices if d['udid'] == args.simulator), None)
    if not device or not device['name'].startswith('VisionStream Automation Lab') or device['state'] != 'Booted':
        raise SystemExit('Use a booted dedicated VisionStream Automation Lab simulator.')
    spec = importlib.util.spec_from_file_location('fixture_server', ROOT/'Scripts/serve_fixtures.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    stopped = threading.Event()
    for sig in [signal.SIGTERM, signal.SIGINT]:
        signal.signal(sig, lambda *_: stopped.set())
    with tempfile.TemporaryDirectory(prefix='visionstream-interactive-tls-') as temporary:
        cert = Path(temporary)/'cert.pem'; key = Path(temporary)/'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-sha256', '-nodes',
                        '-keyout', str(key), '-out', str(cert), '-days', '1', '-subj', '/CN=VisionStream automation fixture',
                        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
                        '-addext', 'basicConstraints=critical,CA:TRUE'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['xcrun', 'simctl', 'keychain', args.simulator, 'add-root-cert', str(cert)], env=environment, check=True)
        server = ThreadingHTTPServer(('127.0.0.1', 0), module.Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        record = {'simulator': args.simulator, 'name': device['name'], 'origin': f'https://127.0.0.1:{server.server_port}',
                  'pid': os.getpid(), 'active': True, 'lifetimeSeconds': args.lifetime,
                  'startedUTC': datetime.now(timezone.utc).isoformat(), 'media': 'Original CC0 fixtures only',
                  'testCertificateScope': 'Dedicated simulator only; delete it when finished'}
        args.metadata.parent.mkdir(parents=True, exist_ok=True)
        args.metadata.write_text(json.dumps(record, indent=2)+'\n')
        print(json.dumps(record), flush=True)
        try:
            stopped.wait(args.lifetime)
        finally:
            server.shutdown(); server.server_close(); thread.join()
            record.update(active=False, stoppedUTC=datetime.now(timezone.utc).isoformat())
            args.metadata.write_text(json.dumps(record, indent=2)+'\n')

if __name__ == '__main__':
    main()
