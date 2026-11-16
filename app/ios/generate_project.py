"""Regenerate the self-contained Xcode project after adding native source/test files."""
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def identifier(label):
    return hashlib.sha1(label.encode()).hexdigest()[:24].upper()


def generate():
    objects = []
    def add(label, value):
        objects.append(f'    {identifier(label)} = {{ {value} }};')
        return identifier(label)
    def array(values):
        return '(' + ', '.join(values) + (', ' if values else '') + ')'
    source_refs, source_builds, test_refs, test_builds, resources = [], [], [], [], []
    for folder, refs, builds in [('FamilyHealth', source_refs, source_builds), ('FamilyHealthTests', test_refs, test_builds)]:
        for path in sorted((ROOT / folder).glob('*.swift')):
            ref = add(folder + path.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path.name}"; sourceTree = "<group>";')
            refs.append(ref)
            builds.append(add('build' + folder + path.name, f'isa = PBXBuildFile; fileRef = {ref};'))
    for path in sorted((ROOT / 'FamilyHealthTests').glob('*.json')):
        ref = add('fixture' + path.name, f'isa = PBXFileReference; lastKnownFileType = text.json; path = "{path.name}"; sourceTree = "<group>";')
        test_refs.append(ref)
        resources.append(add('resource' + path.name, f'isa = PBXBuildFile; fileRef = {ref};'))
    for name, kind in [('Info.plist', 'text.plist.xml'), ('Info-Debug.plist', 'text.plist.xml'), ('FamilyHealth.entitlements', 'text.plist.entitlements')]:
        source_refs.append(add(name, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = "{name}"; sourceTree = "<group>";'))
    app = add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = FamilyHealth.app; sourceTree = BUILT_PRODUCTS_DIR;')
    tests = add('test-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = FamilyHealthTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    sources = add('source-group', f'isa = PBXGroup; children = {array(source_refs)}; path = FamilyHealth; sourceTree = "<group>";')
    testing = add('test-group', f'isa = PBXGroup; children = {array(test_refs)}; path = FamilyHealthTests; sourceTree = "<group>";')
    products = add('products', f'isa = PBXGroup; children = ({app}, {tests}); name = Products; sourceTree = "<group>";')
    group = add('root-group', f'isa = PBXGroup; children = ({sources}, {testing}, {products}); sourceTree = "<group>";')
    source_phase = add('source-phase', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(source_builds)}; runOnlyForDeploymentPostprocessing = 0;')
    test_phase = add('test-phase', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(test_builds)}; runOnlyForDeploymentPostprocessing = 0;')
    resource_phase = add('test-resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resources)}; runOnlyForDeploymentPostprocessing = 0;')
    frameworks = add('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    test_frameworks = add('test-frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    project = identifier('project')
    target = identifier('target')
    test_target = identifier('test-target')
    dependency_proxy = add('dependency-proxy', f'isa = PBXContainerItemProxy; containerPortal = {project}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = FamilyHealth;')
    dependency = add('test-dependency', f'isa = PBXTargetDependency; target = {target}; targetProxy = {dependency_proxy};')
    project_configs, app_configs, test_configs = [], [], []
    for name in ['Debug', 'Release']:
        debug = name == 'Debug'
        settings = 'CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 16.0; SWIFT_VERSION = 5.0;'
        settings += ' SWIFT_STRICT_CONCURRENCY = minimal;'
        if debug:
            settings += ' ENABLE_TESTABILITY = YES; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; GCC_OPTIMIZATION_LEVEL = 0; SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";'
        else:
            settings += ' SWIFT_COMPILATION_MODE = wholemodule; VALIDATE_PRODUCT = YES; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
        project_configs.append(add('project-' + name, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {name};'))
        info = 'Info-Debug.plist' if debug else 'Info.plist'
        shared = 'CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0; TARGETED_DEVICE_FAMILY = 1; PRODUCT_NAME = "$(TARGET_NAME)"; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";'
        app_configs.append(add('app-' + name, f'isa = XCBuildConfiguration; buildSettings = {{ {shared} CODE_SIGN_ENTITLEMENTS = FamilyHealth/FamilyHealth.entitlements; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = FamilyHealth/{info}; PRODUCT_BUNDLE_IDENTIFIER = com.jiahe.familyhealth; HEALTH_API_BASE_URL = ""; }}; name = {name};'))
        test_configs.append(add('tests-' + name, f'isa = XCBuildConfiguration; buildSettings = {{ {shared} GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = com.jiahe.familyhealth.tests; BUNDLE_LOADER = "$(TEST_HOST)"; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/FamilyHealth.app/FamilyHealth"; }}; name = {name};'))
    def configs(label, refs):
        return add(label, f'isa = XCConfigurationList; buildConfigurations = {array(refs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    project_list, app_list, test_list = configs('project-configs', project_configs), configs('app-configs', app_configs), configs('test-configs', test_configs)
    add('target', f'isa = PBXNativeTarget; buildConfigurationList = {app_list}; buildPhases = ({source_phase}, {frameworks}); buildRules = (); dependencies = (); name = FamilyHealth; productName = FamilyHealth; productReference = {app}; productType = "com.apple.product-type.application";')
    add('test-target', f'isa = PBXNativeTarget; buildConfigurationList = {test_list}; buildPhases = ({test_phase}, {test_frameworks}, {resource_phase}); buildRules = (); dependencies = ({dependency}); name = FamilyHealthTests; productName = FamilyHealthTests; productReference = {tests}; productType = "com.apple.product-type.bundle.unit-test";')
    add('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 16.0; SystemCapabilities = {{ com.apple.HealthKit = {{ enabled = 1; }}; }}; }}; {test_target} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {target}; }}; }}; }}; buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base, "zh-Hans"); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target}, {test_target});')
    path = ROOT / 'FamilyHealth.xcodeproj/project.pbxproj'
    grouped = {}
    for line in objects:
        kind = re.search(r'isa = (\w+);', line).group(1)
        grouped.setdefault(kind, []).append(line)
    sections = []
    for kind in sorted(grouped):
        sections.append(f'/* Begin {kind} section */\n' + '\n'.join(grouped[kind]) + f'\n/* End {kind} section */')
    text = '// !$*UTF8*$!\n{\n  archiveVersion = 1;\n  classes = {};\n  objectVersion = 56;\n  objects = {\n' + '\n\n'.join(sections) + '\n  };\n  rootObject = ' + project + ';\n}\n'
    # Keep reference lists in the standard Xcode form, including their final comma.
    text = re.sub(r'([A-Za-z0-9\"])\);', r'\1, );', text)
    path.write_text(text, encoding='utf-8')
    def reference(id, name, product):
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{id}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:FamilyHealth.xcodeproj"/>'
    app_ref = reference(target, 'FamilyHealth', 'FamilyHealth.app')
    test_ref = reference(test_target, 'FamilyHealthTests', 'FamilyHealthTests.xctest')
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
    (ROOT / 'FamilyHealth.xcodeproj/xcshareddata/xcschemes/FamilyHealth.xcscheme').write_text(scheme, encoding='utf-8')
    print(f'Xcode project: {len(source_builds)} app files, {len(test_builds)} test files, {len(resources)} test resources')


if __name__ == '__main__':
    generate()
