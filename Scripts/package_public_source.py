#!/usr/bin/env python3
"""Prepare a local GitHub source ZIP. Never creates a repository or uploads."""
from pathlib import Path
import argparse,hashlib,json,os,zipfile
ROOT=Path(__file__).resolve().parents[1]
FOLDERS={'Config','Docs','Fixtures','Licenses','Scripts','Submission','Tests','Vendor','VisionStream','VisionStream.xcodeproj'}
FILES={'LICENSE','README.md','THIRD_PARTY_NOTICES.md','Package.swift','.gitignore'}
CONFIG={'Base.xcconfig','AppStore.xcconfig','Local.xcconfig.example','Publication.json.example'}
EXCLUDED={'__pycache__','xcuserdata','Prepared','Generated','.git','ExtractorPackages'}

def collect(root):
    paths=[root/name for name in FILES if (root/name).is_file() and not (root/name).is_symlink()]
    for name in sorted(FOLDERS):
        for folder,dirs,files in os.walk(root/name,followlinks=False):
            dirs[:]=[d for d in dirs if d not in EXCLUDED and not d.endswith('.xcresult') and not (Path(folder)/d).is_symlink() and not (name=='Fixtures' and d=='generated')]
            for filename in files:
                file=Path(folder)/filename
                if file.is_symlink() or filename=='.DS_Store' or file.suffix in {'.pyc','.p12','.p8','.key','.mobileprovision','.provisionprofile','.xcuserstate'}:continue
                if name=='Config' and file.relative_to(root/name).as_posix() not in CONFIG:continue
                paths.append(file)
    return sorted(set(paths))

def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=ROOT/'VisionStream-public-source.zip');p.add_argument('--report',type=Path);args=p.parse_args()
    paths=collect(ROOT)
    with zipfile.ZipFile(args.output,'w',zipfile.ZIP_DEFLATED) as archive:
        for file in paths:archive.write(file,file.relative_to(ROOT))
    with zipfile.ZipFile(args.output) as archive:
        assert archive.testzip() is None
        for file in paths:assert archive.read(file.relative_to(ROOT).as_posix())==file.read_bytes()
        names=archive.namelist()
        assert not any(name.startswith(('LocalMedia/','TestResults/','DerivedData/','.build/')) for name in names)
        assert 'LICENSE' in names and 'Licenses/FFmpeg-LGPL-2.1.txt' in names
    report=dict(fileCount=len(paths),sha256=hashlib.sha256(args.output.read_bytes()).hexdigest(),bytes=args.output.stat().st_size,
                privateReportsAndMediaIncluded=False,ownerSigningConfigIncluded=False,fixtureGenerationRequired=True,repositoryCreated=False,uploaded=False,
                originalCodeLicense='MIT; third-party components retain their licences',
                filesOverGitHub100MiBLimit=[str(file.relative_to(ROOT)) for file in paths if file.stat().st_size>100*1024*1024])
    if args.report:args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))
if __name__=='__main__':main()
