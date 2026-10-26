#!/usr/bin/env python3
"""Package source/evidence and the already-built unsigned archive; never signs."""
import hashlib
import json
import os
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def write_zip(destination, files, relative_to):
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as output:
        for path in sorted(files):
            output.write(path, path.relative_to(relative_to))
    with zipfile.ZipFile(destination) as check:
        if check.testzip() is not None: raise RuntimeError('Archive failed integrity validation')
        count = len(check.namelist())
    print(f'{destination.name}: {count} files, {destination.stat().st_size} bytes; integrity passed')

def main():
    manifest = json.loads((ROOT/'TestResults/release-build-manifest.json').read_text())
    archive = Path(manifest['archive'])
    if manifest['signed'] or not archive.is_relative_to(ROOT/'DerivedData/Archives'):
        raise SystemExit('Expected a local unsigned archive described in the release manifest.')
    executable = archive/'Products/Applications/VisionStream.app/VisionStream'
    if hashlib.sha256(executable.read_bytes()).hexdigest() != manifest['executableSHA256']:
        raise SystemExit('Rebuild manifest does not match the archive executable.')
    source = [ROOT/name for name in ['LICENSE','README.md','THIRD_PARTY_NOTICES.md','Package.swift','.gitignore'] if (ROOT/name).is_file()]
    for name in ['Config','Docs','Fixtures','Licenses','Scripts','Submission','Tests','TestResults','Vendor','VisionStream','VisionStream.xcodeproj']:
        for folder, directories, files in os.walk(ROOT/name):
            directories[:] = [d for d in directories if d not in {'__pycache__','Generated','Prepared'} and not d.endswith('.xcresult')]
            for filename in files:
                path = Path(folder)/filename
                if filename in {'Local.xcconfig','Publication.json','Publication.xcconfig','AppStoreLocal.xcconfig','.DS_Store','package-checksums.txt'} or path.suffix in {'.ppm','.pyc'} or path.is_symlink(): continue
                source.append(path)
    source_zip = ROOT/'VisionStream-source.zip'
    device_zip = ROOT/'VisionStream-VisionPro-unsigned.xcarchive.zip'
    write_zip(source_zip, source, ROOT)
    write_zip(device_zip, [p for p in archive.rglob('*') if p.is_file() and not p.is_symlink()], archive.parent)
    checksums = ''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in [source_zip,device_zip])
    (ROOT/'TestResults/package-checksums.txt').write_text(checksums)

if __name__ == '__main__': main()
