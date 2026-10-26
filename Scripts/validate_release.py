#!/usr/bin/env python3
"""Read-only source/archive/package consistency check. Run after packaging."""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def require(condition, message):
    if not condition:
        raise SystemExit(message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def verify_zip(path, base):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), 'Duplicate ZIP entries')
        require(archive.testzip() is None, 'ZIP integrity failed')
        for name in names:
            relative = Path(name)
            require(not relative.is_absolute() and '..' not in relative.parts, 'Unsafe ZIP entry')
            file = base / relative
            require(file.is_file() and not file.is_symlink(), 'Packaged file is missing or linked')
            require(archive.read(name) == file.read_bytes(), 'Packaged file differs: ' + name)
        return len(names)

def main():
    manifest = json.loads((ROOT/'TestResults/release-build-manifest.json').read_text())
    archive = Path(manifest['archive']).resolve()
    require(archive.is_relative_to(ROOT/'DerivedData/Archives'), 'Unexpected archive location')
    app = archive/'Products/Applications/VisionStream.app'
    info = plistlib.loads((app/'Info.plist').read_bytes())
    config = (ROOT/'Config/Base.xcconfig').read_text()
    for key, field, plist in [('MARKETING_VERSION', 'version', 'CFBundleShortVersionString'),
                              ('CURRENT_PROJECT_VERSION', 'build', 'CFBundleVersion')]:
        value = re.search(r'^'+key+r'\s*=\s*(\S+)\s*$', config, re.MULTILINE).group(1)
        require(value == str(manifest[field]) == info[plist], 'Version/build mismatch')
    require(info['MinimumOSVersion'] == '26.0', 'Minimum visionOS mismatch')
    require(not manifest['signed'], 'Expected unsigned personal-use build')
    require(sha(app/'VisionStream') == manifest['executableSHA256'], 'Device executable mismatch')
    for field in ['sourceHashes', 'testSourceHashes']:
        for name, expected in manifest[field].items():
            file = (ROOT/name).resolve()
            require(file.is_relative_to(ROOT), 'Unexpected source path')
            require(sha(file) == expected, 'Source changed: ' + name)
    for name, expected in manifest['resources'].items():
        require(sha(app/name) == expected, 'Resource mismatch: ' + name)
    source_count = verify_zip(ROOT/'VisionStream-source.zip', ROOT)
    device_count = verify_zip(ROOT/'VisionStream-VisionPro-unsigned.xcarchive.zip', archive.parent)
    for line in (ROOT/'TestResults/package-checksums.txt').read_text().splitlines():
        expected, name = line.split('  ', 1)
        require(name in ['VisionStream-source.zip', 'VisionStream-VisionPro-unsigned.xcarchive.zip'], 'Unexpected package name')
        require(sha(ROOT/name) == expected, 'Package checksum mismatch')
    print(json.dumps({'version': manifest['version'], 'build': manifest['build'],
        'sourceFiles': source_count, 'deviceArchiveFiles': device_count,
        'sourceHashes': len(manifest['sourceHashes']), 'testSourceHashes': len(manifest['testSourceHashes']),
        'byteForByteVerified': True}))

if __name__ == '__main__':
    main()
