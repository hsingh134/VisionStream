#!/usr/bin/env python3
"""Read-only local release checks. Passing checks are not App Review approval."""
import argparse
import hashlib
import json
import plistlib
import subprocess
from pathlib import Path
from prepare_submission import configuration

ROOT=Path(__file__).resolve().parents[1]

def inspect(config, archive=None):
    cfg=configuration(config)
    checks=[]
    def check(name,passed,detail,gate=True):
        checks.append(dict(name=name,passed=bool(passed),detail=detail,submissionGate=gate))
    for key in ['publisherName','supportEmail','supportURL','privacyURL','appleTeamID','appBundleID']:
        check(key,bool(cfg[key]),'Owner-provided value is configured; URL ownership/reachability must also be verified.' if cfg[key] else 'Owner value is pending.')
    check('encryption-classification',cfg['usesNonExemptEncryption'] is not None,
          'A publisher decision is required for bundled OpenSSL; do not assume an OS-only exemption.')
    icon=ROOT/'VisionStream/Assets.xcassets/AppIcon.solidimagestack'
    check('layered-icon',all((icon/(layer+'.solidimagestacklayer/Content.imageset/Layer.png')).is_file() for layer in ['Front','Middle','Back']), 'Original three-layer icon; compiled icon also checked in the archive.')
    check('privacy-policy-and-licences',all((ROOT/path).is_file() for path in ['VisionStream/Resources/PrivacyPolicy.txt','Licenses/EmbeddedRuntime.txt','Licenses/Apache-2.0.txt','Licenses/FFmpeg-LGPL-2.1.txt','Licenses/VisionStream-MIT.txt','LICENSE']), 'Policy and complete notices bundled and reachable in Browser settings.')
    manifest=plistlib.loads((ROOT/'VisionStream/Resources/PrivacyInfo.xcprivacy').read_bytes())
    check('privacy-manifest',manifest.get('NSPrivacyTracking') is False and manifest.get('NSPrivacyCollectedDataTypes')==[] and len(manifest.get('NSPrivacyAccessedAPITypes',[]))>=4,'Local processing and no automatic collection declared; reevaluate before adding analytics/support uploads.')
    ff=json.loads((ROOT/'Vendor/FFmpeg/build-manifest.json').read_text())
    source=ROOT/'Vendor/FFmpeg/ffmpeg-9.0.2.tar.xz'
    check('remux-source-and-build',not ff['GPL'] and not ff['nonfree'] and not ff['network'] and hashlib.sha256(source.read_bytes()).hexdigest()==ff['sourceSHA256'],'Corresponding source, build recipe and separate LGPL dynamic library included; public distribution obligations remain the publisher’s responsibility.')
    metadata=ROOT/'Submission/Prepared/metadata.json'
    meta=json.loads(metadata.read_text()) if metadata.exists() else {}
    check('metadata-lengths',bool(meta) and 0<len(meta.get('name',''))<=30 and 0<len(meta.get('subtitle',''))<=30 and len(meta.get('description',''))<=4000 and len(meta.get('keywords',''))<=100,'Prepared general-purpose browser description within text limits.')
    check('source-authorization-review',False,'Saving discovered third-party streams needs documented source permission and review under guideline 5.2.3. Listed documents are not automatically accepted as proof: '+str(len(cfg['sourceAuthorizations']))+' supplied.')
    check('public-support-and-policy-verification',False,'Publish the prepared pages on the owner’s site and verify public HTTPS access/content; no site has been published by this tool.')
    check('physical-headset-release-check',False,'Simulator tests do not verify binocular comfort, gaze/pinch, sustained memory/thermal behavior or device provisioning.')
    identity=subprocess.run(['security','find-identity','-v','-p','codesigning'],capture_output=True,text=True,check=False)
    check('distribution-identity','Apple Distribution:' in identity.stdout,'A valid Apple Distribution identity and paid programme membership are needed for an App Store export; no credentials are read or printed.')
    if archive:
        app=archive/'Products/Applications/VisionStream.app'
        info=plistlib.loads((app/'Info.plist').read_bytes())
        check('archive-icon',bool(info.get('CFBundleIcons')) and (app/'Assets.car').is_file(),'Compiled visionOS icon metadata and asset catalogue present.')
        check('archive-identity',bool(cfg['appBundleID']) and info.get('CFBundleIdentifier')==cfg['appBundleID'],'Personal-use identifiers are not silently treated as registered distribution identities.')
        check('archive-encryption-answer',cfg['usesNonExemptEncryption'] is not None and info.get('ITSAppUsesNonExemptEncryption')==cfg['usesNonExemptEncryption'],'Encryption declaration must reach the actual archived Info.plist.')
        signed=subprocess.run(['codesign','-d','--verbose=2',str(app)],capture_output=True,text=True,check=False)
        check('archive-distribution-signature',signed.returncode==0 and 'Authority=Apple Distribution:' in signed.stderr,'An unsigned or ad-hoc build cannot be uploaded to App Store Connect.')
    else:check('distribution-archive',False,'No signed distribution archive was supplied.')
    return dict(readyForSubmission=all(item['passed'] for item in checks if item['submissionGate']),checks=checks,
                scope='Local preparation only; no enrollment, purchase, publication, upload or Apple validation performed.')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--config',type=Path,default=ROOT/'Config/Publication.json');parser.add_argument('--archive',type=Path);parser.add_argument('--output',type=Path);parser.add_argument('--strict',action='store_true');args=parser.parse_args()
    result=inspect(args.config,args.archive)
    payload=json.dumps(result,indent=2)+'\n'
    if args.output:args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(payload)
    print(payload)
    if args.strict and not result['readyForSubmission']:raise SystemExit(1)
if __name__=='__main__':main()
