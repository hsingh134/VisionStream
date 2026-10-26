#!/usr/bin/env python3
"""Build a reviewable archive locally. Never enrolls, purchases or uploads."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
from prepare_submission import configuration

ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser();p.add_argument('--unsigned',action='store_true',help='Compile/validate structure only; cannot install on hardware or upload');p.add_argument('--archive',type=Path,required=True);p.add_argument('--derived-data',type=Path,default=ROOT/'DerivedData/DeviceRelease');p.add_argument('--config',type=Path,default=ROOT/'Config/Publication.json');p.add_argument('--export',type=Path,help='Optional local export of a signed archive, without upload');args=p.parse_args()
    if args.archive.exists():raise SystemExit('Use a new archive path; existing archives are preserved.')
    if args.unsigned and args.export:raise SystemExit('An unsigned archive cannot be exported for distribution.')
    cfg=configuration(args.config)
    if not args.unsigned:
        required=['appleTeamID','appBundleID','publisherName','supportEmail','supportURL','privacyURL']
        if any(not cfg[key] for key in required) or cfg['usesNonExemptEncryption'] is None:raise SystemExit('Signing/publication fields are incomplete. Simulator and unsigned builds remain available free of charge.')
        identities=subprocess.run(['security','find-identity','-v','-p','codesigning'],capture_output=True,text=True,check=True).stdout
        if 'Apple Distribution:' not in identities:raise SystemExit('No valid Apple Distribution identity. Sign in and configure signing directly in Xcode; no account purchase is performed here.')
    env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    subprocess.run([sys.executable,str(ROOT/'Scripts/prepare_submission.py'),'--config',str(args.config),'--write-build-config'],cwd=ROOT,env=env,check=True)
    command=['xcodebuild','-project','VisionStream.xcodeproj','-scheme','VisionStream-AppStore','-configuration','AppStore','-destination','generic/platform=visionOS','-derivedDataPath',str(args.derived_data),'-archivePath',str(args.archive),'archive']
    if args.unsigned:command+=['CODE_SIGNING_ALLOWED=NO']
    subprocess.run(command,cwd=ROOT,env=env,check=True)
    if args.export:subprocess.run(['xcodebuild','-exportArchive','-archivePath',str(args.archive),'-exportPath',str(args.export),'-exportOptionsPlist',str(ROOT/'Submission/Prepared/ExportOptions.plist')],cwd=ROOT,env=env,check=True)
if __name__=='__main__':main()
