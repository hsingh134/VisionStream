#!/usr/bin/env python3
"""Deterministic checked-in Xcode project; no XcodeGen or third-party packages required."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
objects = {}
def obj(name, value):
    key = ident(name)
    objects[key] = value
    return key
def quote(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'
def array(values):
    return '(' + ', '.join(values) + ',)'
def settings(values):
    return '{' + ' '.join(f'{key} = {value};' for key, value in values.items()) + '}'
def config_list(name, base):
    configs = []
    for mode in ['Debug', 'Release', 'AppStore']:
        values = dict(base)
        values['SWIFT_OPTIMIZATION_LEVEL'] = quote('-Onone' if mode == 'Debug' else '-O')
        values['DEBUG_INFORMATION_FORMAT'] = quote('dwarf' if mode == 'Debug' else 'dwarf-with-dsym')
        if mode == 'Debug': values['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
        config_ref=ident("Config/AppStore.xcconfig") if mode == "AppStore" else ident("baseconfig")
        configs.append(obj(name + mode, f'{{isa = XCBuildConfiguration; baseConfigurationReference = {config_ref}; buildSettings = {settings(values)}; name = {mode};}}'))
    return obj(name + 'configs', f'{{isa = XCConfigurationList; buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}}')

sources = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT/'VisionStream').rglob('*.swift'))
sources += sorted(p.relative_to(ROOT).as_posix() for p in (ROOT/'VisionStream').rglob('*.m'))
sources += ['VisionStream/Rendering/StereoVideo.metal']
resources = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT/'VisionStream/Resources').iterdir() if p.is_file())
resources += ['THIRD_PARTY_NOTICES.md']
resources += sorted(p.relative_to(ROOT).as_posix() for p in (ROOT/'Licenses').glob('*.txt'))
resources += ['VisionStream/Resources/ExtractorPython', 'Vendor/ExtractorPackages', 'VisionStream/Assets.xcassets']
framework = 'Vendor/Python.xcframework'
media_framework = 'Vendor/VisionStreamMedia.xcframework'
frameworks=[framework,media_framework]
headers = ['VisionStream/Extraction/ExtractorBridge.h']
tests = sorted(p.relative_to(ROOT).as_posix() for folder in ['CoreTests', 'VisionOSTests'] for p in (ROOT/'Tests'/folder).rglob('*.swift'))
file_refs, build_refs = {}, {}
types = {'.xcassets':'folder.assetcatalog', '.xcprivacy': 'text.xml', '.swift': 'sourcecode.swift', '.m': 'sourcecode.c.objc', '.h': 'sourcecode.c.h', '.xcframework': 'wrapper.xcframework', '.metal': 'sourcecode.metal', '.js': 'sourcecode.javascript', '.html': 'text.html', '.usda': 'text', '.md': 'text', '.txt': 'text', '.xcconfig': 'text.xcconfig', '.plist': 'text.plist.xml'}
for path in sources + resources + tests + headers + frameworks + ['Config/Base.xcconfig', 'Config/AppStore.xcconfig', 'Config/Local.xcconfig.example', 'VisionStream/Info.plist']:
    name = 'baseconfig' if path == 'Config/Base.xcconfig' else path
    file_type = 'folder' if path in ['VisionStream/Resources/ExtractorPython', 'Vendor/ExtractorPackages'] else types.get(Path(path).suffix, 'text')
    file_refs[path] = obj(name, f'{{isa = PBXFileReference; lastKnownFileType = {file_type}; path = {quote(path)}; sourceTree = SOURCE_ROOT;}}')
    if path in sources + resources + tests + frameworks:
        build_refs[path] = obj('build'+path, f'{{isa = PBXBuildFile; fileRef = {file_refs[path]};}}')
app_product = obj('product-app', '{isa = PBXFileReference; explicitFileType = wrapper.application; path = VisionStream.app; sourceTree = BUILT_PRODUCTS_DIR;}')
test_product = obj('product-test', '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = VisionStreamTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
products = obj('products', f'{{isa = PBXGroup; children = {array([app_product, test_product])}; name = Products; sourceTree = "<group>";}}')
main = obj('main', f'{{isa = PBXGroup; children = {array(list(file_refs.values())+[products])}; sourceTree = "<group>";}}')
def phase(name, isa, paths):
    return obj(name, f'{{isa = {isa}; buildActionMask = 2147483647; files = {array([build_refs[p] for p in paths]) if paths else "()"}; runOnlyForDeploymentPostprocessing = 0;}}')
embedded = obj('embedded-python', f'{{isa = PBXBuildFile; fileRef = {file_refs[framework]}; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, );}};}}')
embedded_media = obj('embedded-media', f'{{isa = PBXBuildFile; fileRef = {file_refs[media_framework]}; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, );}};}}')
embed_phase = obj('embed-python', f'{{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 10; files = {array([embedded,embedded_media])}; name = "Embed runtimes"; runOnlyForDeploymentPostprocessing = 0;}}')
install_script = obj('install-python', '{isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); alwaysOutOfDate = 1; '
    'inputPaths = ("$(SRCROOT)/Vendor/Python.xcframework", "$(SRCROOT)/Scripts/install_embedded_python.sh", '
    '"$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/ExtractorPython", "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/ExtractorPackages"); '
    'outputPaths = ("$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/python", "$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)"); '
    'name = "Install bundled Python"; runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/bash; '
    'shellScript = "bash \\\"$PROJECT_DIR/Scripts/install_embedded_python.sh\\\""; showEnvVarsInLog = 0;}')
app_phases = [phase('sources', 'PBXSourcesBuildPhase', sources), phase('frameworks', 'PBXFrameworksBuildPhase', frameworks), phase('resources', 'PBXResourcesBuildPhase', resources), install_script, embed_phase]
test_phases = [phase('test-sources','PBXSourcesBuildPhase', tests), phase('test-frameworks','PBXFrameworksBuildPhase', [media_framework])]
project_configs = config_list('project', {'ALWAYS_SEARCH_USER_PATHS':'NO', 'CLANG_ENABLE_MODULES':'YES', 'SWIFT_VERSION':'6.0'})
app_configs = config_list('app', {'PRODUCT_NAME': 'VisionStream', 'PRODUCT_MODULE_NAME':'VisionStream',
    'SWIFT_OBJC_BRIDGING_HEADER':quote('VisionStream/Extraction/ExtractorBridge.h'),
    'CLANG_ENABLE_OBJC_ARC':'YES',
    # The pinned framework packager copies/rewrites extension modules and signs
    # their bundles. Xcode's script input sandbox cannot model those dynamic paths.
    'ENABLE_USER_SCRIPT_SANDBOXING':'NO',
    'LD_RUNPATH_SEARCH_PATHS':array([quote('$(inherited)'), quote('@executable_path/Frameworks')])})
test_configs = config_list('test', {'PRODUCT_NAME':'VisionStreamTests', 'PRODUCT_BUNDLE_IDENTIFIER':'personal.visionstream.browser.tests',
    'GENERATE_INFOPLIST_FILE':'YES', 'INFOPLIST_FILE':'""', 'TEST_HOST':'"$(BUILT_PRODUCTS_DIR)/VisionStream.app/VisionStream"',
    'BUNDLE_LOADER':'"$(TEST_HOST)"', 'PRODUCT_MODULE_NAME':'VisionStreamTests'})
app_target = obj('app-target', f'{{isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {array(app_phases)}; buildRules = (); dependencies = (); name = VisionStream; productName = VisionStream; productReference = {app_product}; productType = "com.apple.product-type.application";}}')
proxy = obj('proxy', f'{{isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = VisionStream;}}')
dependency = obj('dependency', f'{{isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};}}')
test_target = obj('test-target', f'{{isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = {array(test_phases)}; buildRules = (); dependencies = {array([dependency])}; name = VisionStreamTests; productName = VisionStreamTests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test";}}')
project = obj('project', f'{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 2600; LastUpgradeCheck = 2600; TargetAttributes = {{{app_target} = {{CreatedOnToolsVersion = 26.0; ProvisioningStyle = Automatic;}}; {test_target} = {{CreatedOnToolsVersion = 26.0; TestTargetID = {app_target};}};}};}}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 15.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([app_target,test_target])};}}')
directory = ROOT/'VisionStream.xcodeproj'
directory.mkdir(exist_ok=True)
(directory/'project.pbxproj').write_text('// !$*UTF8*$!\n{\narchiveVersion = 1;\nclasses = {};\nobjectVersion = 60;\nobjects = {\n' + '\n'.join(f'{key} = {value};' for key,value in objects.items()) + f'\n}};\nrootObject = {project};\n}}\n')
shared = directory/'xcshareddata/xcschemes'
shared.mkdir(parents=True, exist_ok=True)
def reference(key, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{key}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:VisionStream.xcodeproj"/>'
app_ref = reference(app_target, 'VisionStream.app')
test_ref = reference(test_target, 'VisionStreamTests.xctest')
(shared/'VisionStream.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO" parallelizable="NO">{test_ref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
(shared/'VisionStream-AppStore.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="NO" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="AppStore" launchStyle="0" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="AppStore" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="AppStore"/><ArchiveAction buildConfiguration="AppStore" revealArchiveInOrganizer="YES"/>
</Scheme>''')
workspace = directory/'project.xcworkspace'
workspace.mkdir(exist_ok=True)
(workspace/'contents.xcworkspacedata').write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>')
print(f'Generated Xcode project with {len(sources)} source files, {len(resources)} resources and {len(tests)} test files.')
