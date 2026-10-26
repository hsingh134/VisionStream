#!/usr/bin/env python3
"""Unattended native visionOS scene checks, including while the Mac is locked.

The app calls its production form/transport actions from an explicitly enabled
simulator-only test runner. This is scene integration testing, not XCUITest or
synthetic user input. No private websites or saved user simulator sessions run.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = 'personal.visionstream.browser'
DEFAULT_CASES = ['forms', 'mp4', 'hls', 'library', 'library-hls', 'cancel', 'unsupported', 'reentry']

def read_json(path):
    try: return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError): return None

def completed_result(record, identifier, scenario):
    return (isinstance(record, dict) and type(record.get('schemaVersion')) is int
            and record['schemaVersion'] == 1 and record.get('identifier') == identifier
            and record.get('scenario') == scenario and record.get('status') in ['passed', 'failed'])

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime', choices=['26.0', '27.0'], default='26.0')
    parser.add_argument('--simulator', help='Optional existing dedicated Automation Lab simulator')
    parser.add_argument('--fixture-session', type=Path, help='Optional existing fixture metadata for that simulator')
    parser.add_argument('--build-root', type=Path, default=ROOT/'DerivedData/OnDeviceClean')
    parser.add_argument('--cases', nargs='+', choices=DEFAULT_CASES+['auto-play', 'soak', 'saved-state', 'downloads', 'finder', 'interrupted', 'quality', 'quality4k', 'controls', 'controls-format', 'controls-quality'])
    parser.add_argument('--public-extraction', action='store_true', help='Opt into the fixed public-domain NASA finder scenario')
    parser.add_argument('--soak-seconds', type=int, default=600, help='Duration of the opt-in soak case, from 60 to 1800 seconds')
    parser.add_argument('--case-timeout', type=int, default=180)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--keep-simulator', action='store_true')
    args = parser.parse_args()
    if not 20 <= args.case_timeout <= 300: parser.error('Choose a case timeout between 20 and 300 seconds.')
    if not 60 <= args.soak_seconds <= 1800: parser.error('Choose a soak duration between 60 and 1800 seconds.')
    cases = args.cases or DEFAULT_CASES + (['finder'] if args.public_extraction else [])
    if 'finder' in cases and not args.public_extraction: parser.error('finder requires --public-extraction.')
    environment = dict(os.environ); environment['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'
    def command(*parts, check=True):
        return subprocess.run(list(parts), env=environment, capture_output=True, text=True, check=check, timeout=120)
    def simctl(*parts, check=True): return command('xcrun', 'simctl', *parts, check=check)
    app = args.build_root.resolve()/'Build/Products/Release-xrsimulator/VisionStream.app'
    if not app.is_dir(): raise SystemExit('Build the Release simulator app first.')
    info = plistlib.loads((app/'Info.plist').read_bytes())
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    output = args.output or ROOT/'TestResults'/f'Scenes-{args.runtime}-{stamp}'
    output.mkdir(parents=True, exist_ok=False)
    created = args.simulator is None
    udid = args.simulator or simctl('create', 'VisionStream Automation Lab '+args.runtime+'-'+uuid.uuid4().hex[:6],
        'com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro-4K', 'com.apple.CoreSimulator.SimRuntime.xrOS-'+args.runtime.replace('.', '-')).stdout.strip()
    inventory = json.loads(simctl('list', 'devices', '-j').stdout)
    device = next((d for devices in inventory['devices'].values() for d in devices if d['udid'] == udid), None)
    if not device or not device['name'].startswith('VisionStream Automation Lab'):
        raise SystemExit('Only a dedicated VisionStream Automation Lab simulator may be used.')
    session = None; session_log = None; results = []
    metadata = {'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
                'runtime': args.runtime, 'simulator': udid, 'createdSimulator': created,
                'casesRequested': cases, 'publicExtractionEnabled': args.public_extraction,
                'testKind': 'Real app scenes and shared actions; no synthetic touch/keyboard',
                'status': 'running', 'cases': results}
    def save(): (output/'summary.json').write_text(json.dumps(metadata, indent=2)+'\n')
    save()
    try:
        if device['state'] != 'Booted': simctl('boot', udid)
        simctl('bootstatus', udid, '-b')
        if args.fixture_session:
            fixture = read_json(args.fixture_session)
            if not fixture or fixture.get('simulator') != udid or not fixture.get('active'):
                raise RuntimeError('Fixture session does not match the running dedicated simulator.')
        else:
            fixture_path = output/'fixture-session.json'
            session_log = (output/'fixture-server.txt').open('w')
            session = subprocess.Popen([sys.executable, str(ROOT/'Scripts/start_simulator_fixture_session.py'),
                '--simulator', udid, '--metadata', str(fixture_path), '--lifetime', '7200'],
                env=environment, stdout=session_log, stderr=subprocess.STDOUT)
            deadline = time.monotonic()+20
            fixture = None
            while time.monotonic() < deadline:
                fixture = read_json(fixture_path)
                if fixture and fixture.get('active'): break
                if session.poll() is not None: raise RuntimeError('Fixture server failed to start.')
                time.sleep(0.1)
            if not fixture or not fixture.get('active'): raise RuntimeError('Fixture server did not become ready.')
        simctl('install', udid, str(app))
        container = Path(simctl('get_app_container', udid, BUNDLE, 'data').stdout.strip())
        folder = container/'Library/Caches/VisionStreamAutomation'
        for name in cases:
            identifier = str(uuid.uuid4())
            launched_at = time.time()
            child = dict(environment)
            child.update(SIMCTL_CHILD_VISIONSTREAM_SIMULATOR_OBSERVE='1', SIMCTL_CHILD_VISIONSTREAM_SCENE_TEST=name,
                         SIMCTL_CHILD_VISIONSTREAM_SCENE_TEST_ID=identifier,
                         SIMCTL_CHILD_VISIONSTREAM_TEST_ORIGIN=fixture['origin'])
            if name == 'soak': child['SIMCTL_CHILD_VISIONSTREAM_TEST_SOAK_SECONDS'] = str(args.soak_seconds)
            if args.public_extraction: child['SIMCTL_CHILD_VISIONSTREAM_TEST_PUBLIC_EXTRACTOR'] = '1'
            launch = subprocess.run(['xcrun', 'simctl', 'launch', '--terminate-running-process', udid, BUNDLE],
                                    env=child, capture_output=True, text=True, timeout=60)
            (output/(name+'-launch.txt')).write_text(launch.stdout+launch.stderr)
            if launch.returncode: raise RuntimeError('Simulator app launch failed.')
            deadline = time.monotonic()+args.case_timeout+(args.soak_seconds if name == 'soak' else 0)
            result = None
            while time.monotonic() < deadline:
                current = read_json(folder/'Scenario.json')
                if completed_result(current, identifier, name):
                    result = current; break
                time.sleep(0.2)
            if result is None:
                result = {'identifier': identifier, 'scenario': name, 'status': 'failed', 'failureCode': 'outer-scenario-timeout'}
                pending = read_json(folder/'Scenario.json')
                if pending and pending.get('identifier') == identifier: result['lastProgress'] = pending
            state = read_json(folder/'State.json')
            if state and state.get('observedEpoch', 0) >= launched_at: result['finalState'] = state
            (output/(name+'.json')).write_text(json.dumps(result, indent=2)+'\n')
            results.append({'scenario': name, 'status': result['status'], 'failureCode': result.get('failureCode'),
                            'passedChecks': len(result.get('checks', [])), 'evidence': str(output/(name+'.json'))})
            save(); print(json.dumps(results[-1]), flush=True)
            simctl('terminate', udid, BUNDLE, check=False)
            if result['status'] != 'passed': break
        metadata['status'] = 'passed' if len(results) == len(cases) and all(r['status'] == 'passed' for r in results) else 'failed'
    except Exception as error:
        metadata.update(status='failed', harnessError=type(error).__name__)
        raise
    finally:
        simctl('terminate', udid, BUNDLE, check=False)
        if session:
            session.terminate()
            try: session.wait(timeout=10)
            except subprocess.TimeoutExpired: session.kill(); session.wait()
        if session_log: session_log.close()
        if created and not args.keep_simulator:
            simctl('shutdown', udid, check=False); simctl('delete', udid)
            metadata['testSimulatorDeleted'] = True
        save()
    print(json.dumps({'status': metadata['status'], 'summary': str(output/'summary.json')}), flush=True)
    if metadata['status'] != 'passed': raise SystemExit(1)

if __name__ == '__main__': main()
