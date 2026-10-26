#!/bin/bash
set -euo pipefail
# The checksum-verified BeeWare helper repackages bundled extension modules as
# signed frameworks, as required by Apple's embedded-Python distribution model.
source "$PROJECT_DIR/Vendor/Python.xcframework/build/utils.sh"
# Unsigned development builds still need ad-hoc signatures on extension modules
# for the arm64 simulator. A signing-enabled device build uses the selected team.
export EXPANDED_CODE_SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
export EXPANDED_CODE_SIGN_IDENTITY_NAME="${EXPANDED_CODE_SIGN_IDENTITY_NAME:-Ad hoc development}"
install_python Vendor/Python.xcframework ExtractorPython ExtractorPackages
