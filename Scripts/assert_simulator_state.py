#!/usr/bin/env python3
"""Read-only assertions on opt-in redacted simulator telemetry.

This never injects input or drives UI. Use Device Hub/CUA for real interactions;
the file proves their observed model/scene/player outcomes without clipboard use.
"""
import argparse
import json
import math
import os
from pathlib import Path
import subprocess
import time

def field(record, path):
    value = record
    for part in path.split('.'):
        value = value[int(part)] if isinstance(value, list) else value[part]
    return value

def expression(text):
    path, separator, raw = text.partition('=')
    if not separator or not path or any(not p.replace('_', '').isalnum() for p in path.split('.')):
        raise argparse.ArgumentTypeError('Use a dotted.field=value expression.')
    try: value = json.loads(raw)
    except json.JSONDecodeError: value = raw
    return path, value

def matches(record, equals, minimums, now=None, after=0):
    now = time.time() if now is None else now
    observed = record.get('observedEpoch', 0)
    if type(record.get('schemaVersion')) is not int or record.get('schemaVersion') != 1 or not isinstance(observed, (int, float)) or isinstance(observed, bool):
        return False
    if not math.isfinite(observed) or not after <= observed <= now + 1 or now - observed > 3:
        return False
    try:
        for path, expected in equals:
            actual = field(record, path)
            if type(actual) is not type(expected) and not (type(actual) in (int, float) and type(expected) in (int, float)):
                return False
            if actual != expected: return False
        for path, expected in minimums:
            actual = field(record, path)
            if type(actual) not in (int, float) or type(expected) not in (int, float): return False
            if not math.isfinite(actual) or not math.isfinite(expected) or actual < expected: return False
        return True
    except (KeyError, IndexError, TypeError, ValueError):
        return False

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--expect', action='append', type=expression, default=[])
    parser.add_argument('--at-least', action='append', type=expression, default=[])
    parser.add_argument('--timeout', type=float, default=20)
    parser.add_argument('--after', type=float, default=0, help='Require a snapshot after this epoch time')
    parser.add_argument('--stable', help='Verify a numeric field stays within tolerance')
    parser.add_argument('--advancing', help='Verify a numeric field advances by at least tolerance')
    parser.add_argument('--duration', type=float, default=1)
    parser.add_argument('--tolerance', type=float, default=0.2)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not 0 < args.timeout <= 180 or not 0.5 <= args.duration <= 10 or args.tolerance < 0:
        parser.error('Choose bounded positive timing/tolerance values.')
    if args.stable and args.advancing: parser.error('Choose stable or advancing, not both.')
    environment = dict(os.environ); environment['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'
    inventory = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '-j'], env=environment))
    device = next((d for devices in inventory['devices'].values() for d in devices if d['udid'] == args.simulator), None)
    if not device or not device['name'].startswith('VisionStream Automation Lab'):
        raise SystemExit('Use a dedicated VisionStream Automation Lab simulator.')
    result = subprocess.run(['xcrun', 'simctl', 'get_app_container', args.simulator,
                             'personal.visionstream.browser', 'data'], env=environment, capture_output=True, text=True, check=True)
    source = Path(result.stdout.strip())/'Library/Caches/VisionStreamAutomation/State.json'
    deadline = time.monotonic() + args.timeout
    last = None; baseline = None; stable_since = None; previous_sequence = None; success = False
    while time.monotonic() < deadline:
        try: last = json.loads(source.read_text())
        except (OSError, json.JSONDecodeError): time.sleep(0.1); continue
        if matches(last, args.expect, args.at_least, after=args.after):
            if not (args.stable or args.advancing): success = True; break
            try: value = field(last, args.stable or args.advancing)
            except (KeyError, IndexError, TypeError, ValueError): value = None
            if type(value) in (int, float) and math.isfinite(value):
                if baseline is None:
                    baseline = value; stable_since = time.monotonic(); previous_sequence = last.get('sequence')
                elif last.get('sequence') != previous_sequence:
                    if args.stable and abs(value - baseline) > args.tolerance:
                        baseline = value; stable_since = time.monotonic()
                    elif time.monotonic() - stable_since >= args.duration:
                        success = args.stable is not None or value - baseline >= args.tolerance
                        if success: break
        else: baseline = None; stable_since = None
        time.sleep(0.1)
    evidence = {'outcome': 'passed' if success else 'failed', 'simulator': args.simulator,
                'assertions': {'equals': args.expect, 'minimums': args.at_least, 'stable': args.stable,
                               'advancing': args.advancing, 'duration': args.duration, 'tolerance': args.tolerance},
                'snapshot': last}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(evidence, indent=2)+'\n')
    print(json.dumps({'outcome': evidence['outcome'], 'sequence': last.get('sequence') if last else None,
                      'stage': last.get('report', {}).get('playbackStage') if last else None}))
    if not success: raise SystemExit(1)

if __name__ == '__main__': main()
