#!/usr/bin/env python3
"""Test AVFoundation streaming on this Mac; the production app still requires HTTPS."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import threading
from http.server import ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('fixture_server', ROOT/'Scripts/serve_fixtures.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
with tempfile.TemporaryDirectory(prefix='visionstream-avprobe-') as directory:
    binary = Path(directory)/'probe'; cache = Path(directory)/'modules'; cache.mkdir()
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', '-module-cache-path', str(cache),
                    str(ROOT/'Tests/MacStreamingProbe.swift'), '-o', str(binary)],check=True)
    server = ThreadingHTTPServer(('127.0.0.1',0), module.Handler)
    thread = threading.Thread(target=server.serve_forever,daemon=True); thread.start()
    try:
        # Loopback HTTP is confined to this desktop probe. No ATS settings or trust stores are changed.
        subprocess.run([str(binary), f'http://127.0.0.1:{server.server_port}'],check=True,timeout=180)
    finally:
        server.shutdown(); server.server_close(); thread.join()
