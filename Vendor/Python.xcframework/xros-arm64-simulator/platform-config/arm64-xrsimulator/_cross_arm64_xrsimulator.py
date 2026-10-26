# A site package that turns a macOS virtual environment
# into an arm64 xrsimulator cross-platform virtual environment
import platform
import subprocess
import sys
import sysconfig

###########################################################################
# sys module patches
###########################################################################
sys.cross_compiling = True
sys.platform = "visionos"
sys.implementation._multiarch = "arm64-xrsimulator"
sys.base_prefix = sysconfig._get_sysconfigdata()["prefix"]
sys.base_exec_prefix = sysconfig._get_sysconfigdata()["prefix"]

###########################################################################
# subprocess module patches
###########################################################################
subprocess._can_fork_exec = True


###########################################################################
# platform module patches
###########################################################################

def cross_system():
    return "visionOS"


def cross_uname():
    return platform.uname_result(
        system="visionOS",
        node="build",
        release="2.0",
        version="",
        machine="arm64",
    )


def cross_ios_ver(system="", release="", model="", is_simulator=False):
    if system == "":
        system = "visionOS"
    if release == "":
        release = "2.0"
    if model == "":
        model = "xrsimulator"

    return platform.IOSVersionInfo(system, release, model, True)


platform.system = cross_system
platform.uname = cross_uname
platform.ios_ver = cross_ios_ver


###########################################################################
# sysconfig module patches
###########################################################################

def cross_get_platform():
    return "visionos-2.0-arm64-xrsimulator"


def cross_get_sysconfigdata_name():
    return "_sysconfigdata__visionos_arm64-xrsimulator"


sysconfig.get_platform = cross_get_platform
sysconfig._get_sysconfigdata_name = cross_get_sysconfigdata_name

# Ensure module-level values cached at time of import are updated.
sysconfig._BASE_PREFIX = sys.base_prefix
sysconfig._BASE_EXEC_PREFIX = sys.base_exec_prefix

# Force sysconfig data to be loaded (and cached).
sysconfig._init_config_vars()
