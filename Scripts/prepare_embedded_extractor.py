#!/usr/bin/env python3
"""Fetch checksum-pinned, published dependencies for the on-device extractor."""
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
from urllib.request import urlopen
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ASSETS = [
    dict(name="Python-3.14-visionOS-support.b13.tar.gz", version="3.14-b13",
         url="https://github.com/beeware/Python-Apple-support/releases/download/3.14-b13/Python-3.14-visionOS-support.b13.tar.gz",
         sha256="c85c8c007092eb45a8737b31578c043fe3d5762ad98ed7a42426ac2d3bf7f22a"),
    dict(name="yt_dlp-2026.10.21-py3-none-any.whl", version="2026.10.21",
         url="https://files.pythonhosted.org/packages/b7/75/ae700ddc7e0b1095fd06cf7e251627dcf4cafcaff460cce92cdc08023b13/yt_dlp-2026.10.21-py3-none-any.whl",
         sha256="94a3a3e2c423129d0bbd2f1be000c4171fa1226c29e251c84aff868f2851c247"),
    dict(name="certifi-2026.10.23-py3-none-any.whl", version="2026.10.23",
         url="https://files.pythonhosted.org/packages/32/d1/a3652fe2c19134d0d15922177821d863cbd7e842d53a21bbe7e8e3a1b5ac/certifi-2026.10.23-py3-none-any.whl",
         sha256="e9b54de76e530bb6cf0ccd036787103acb58fd42ba930ea8bf948ddbaa2f61d1"),
]


def main():
    cache = ROOT / "DerivedData/DependencyArchives"
    vendor = ROOT / "Vendor"
    cache.mkdir(parents=True, exist_ok=True)
    vendor.mkdir(exist_ok=True)
    for asset in ASSETS:
        archive = cache / asset["name"]
        # Reuse only a checksum-verified archive from the feasibility experiment.
        research = ROOT / "DerivedData/OnDeviceExtractor" / asset["name"]
        if not archive.exists() and research.exists():
            shutil.copy2(research, archive)
        if not archive.exists():
            partial = archive.with_suffix(archive.suffix + ".part")
            with urlopen(asset["url"], timeout=60) as source, partial.open("wb") as output:
                shutil.copyfileobj(source, output)
            partial.replace(archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != asset["sha256"]:
            raise SystemExit(f"Checksum mismatch: {asset['name']}. Nothing was installed.")
        if archive.name.endswith(".tar.gz"):
            destination = cache / "PythonSupport"
            if not destination.exists():
                destination.mkdir()
                with tarfile.open(archive) as package:
                    package.extractall(destination, filter="data")
            shutil.copytree(destination / "Python.xcframework", vendor / "Python.xcframework", dirs_exist_ok=True)
            shutil.copy2(destination / "VERSIONS", vendor / "Python-VERSIONS.txt")
            helper = vendor / "Python.xcframework/build/utils.sh"
            # Local MIT-licensed build-helper fix: support workspace paths with spaces.
            helper.write_text(helper.read_text().replace(
                '> ${FULL_EXT%.so}.fwork', '> "${FULL_EXT%.so}.fwork"'))
        else:
            destination = vendor / "ExtractorPackages"
            destination.mkdir(exist_ok=True)
            with zipfile.ZipFile(archive) as package:
                if any(Path(n).is_absolute() or ".." in Path(n).parts for n in package.namelist()):
                    raise SystemExit("Invalid dependency archive path")
                package.extractall(destination)
        print(f"Verified and prepared {asset['name']}")
    lock_path = vendor / "dependencies.lock.json"
    existing = json.loads(lock_path.read_text()) if lock_path.exists() else []
    managed_names = {asset["name"] for asset in ASSETS}
    unrelated = [asset for asset in existing if asset.get("name") not in managed_names]
    lock_path.write_text(json.dumps(ASSETS + unrelated, indent=2) + "\n")


if __name__ == "__main__":
    main()
