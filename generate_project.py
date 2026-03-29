#!/usr/bin/env python3
"""Generate ClaudeLifter.xcodeproj/project.pbxproj"""

import hashlib
import os

def uid(name):
    """Generate a deterministic 24-char hex UUID from a name."""
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()

# Collect all Swift source files
def collect_swift_files(root_dir):
    files = []
    for dirpath, _, filenames in sorted(os.walk(root_dir)):
        for f in sorted(filenames):
            if f.endswith('.swift'):
                rel = os.path.relpath(os.path.join(dirpath, f), '.')
                files.append(rel)
    return files

app_sources = collect_swift_files('ClaudeLifter')
test_sources = collect_swift_files('ClaudeLifterTests')

# IDs for key objects
PROJECT_ID = uid('project')
MAIN_GROUP_ID = uid('mainGroup')
APP_GROUP_ID = uid('appGroup')
TEST_GROUP_ID = uid('testGroup')
PRODUCTS_GROUP_ID = uid('productsGroup')
FRAMEWORKS_GROUP_ID = uid('frameworksGroup')

APP_TARGET_ID = uid('appTarget')
TEST_TARGET_ID = uid('testTarget')

APP_PRODUCT_REF_ID = uid('appProductRef')
TEST_PRODUCT_REF_ID = uid('testProductRef')

APP_BUILD_CONFIG_LIST_ID = uid('appBuildConfigList')
TEST_BUILD_CONFIG_LIST_ID = uid('testBuildConfigList')
PROJECT_BUILD_CONFIG_LIST_ID = uid('projectBuildConfigList')

APP_DEBUG_ID = uid('appDebug')
APP_RELEASE_ID = uid('appRelease')
TEST_DEBUG_ID = uid('testDebug')
TEST_RELEASE_ID = uid('testRelease')
PROJECT_DEBUG_ID = uid('projectDebug')
PROJECT_RELEASE_ID = uid('projectRelease')

APP_SOURCES_PHASE_ID = uid('appSourcesPhase')
TEST_SOURCES_PHASE_ID = uid('testSourcesPhase')
APP_FRAMEWORKS_PHASE_ID = uid('appFrameworksPhase')
TEST_FRAMEWORKS_PHASE_ID = uid('testFrameworksPhase')
APP_RESOURCES_PHASE_ID = uid('appResourcesPhase')

APP_DEP_ID = uid('appDependency')
APP_DEP_PROXY_ID = uid('appDependencyProxy')

# Resources
EXERCISES_JSON_REF_ID = uid('exercises.json_ref')
EXERCISES_JSON_BUILD_ID = uid('exercises.json_build')
ASSETS_REF_ID = uid('Assets.xcassets_ref')
ASSETS_BUILD_ID = uid('Assets.xcassets_build')

# SPM
RESOURCES_GROUP_ID = 'AAAA000000000001RESOURCE'

PACKAGE_REF_ID = uid('swiftAnthropicPackageRef')
PACKAGE_PRODUCT_ID = uid('swiftAnthropicProduct')
PACKAGE_PRODUCT_DEP_ID = uid('swiftAnthropicProductDep')

# Build file and file reference entries
file_refs = []
build_files_app = []
build_files_test = []
group_children_app = {}
group_children_test = {}

for f in app_sources:
    ref_id = uid(f + '_ref')
    build_id = uid(f + '_build')
    file_refs.append((ref_id, f, os.path.basename(f)))
    build_files_app.append((build_id, ref_id, os.path.basename(f)))
    # Group by directory
    d = os.path.dirname(f)
    group_children_app.setdefault(d, []).append(ref_id)

for f in test_sources:
    ref_id = uid(f + '_ref')
    build_id = uid(f + '_build')
    file_refs.append((ref_id, f, os.path.basename(f)))
    build_files_test.append((build_id, ref_id, os.path.basename(f)))
    d = os.path.dirname(f)
    group_children_test.setdefault(d, []).append(ref_id)

# Build group hierarchy
def build_groups(children_map, root_prefix, root_id, root_name):
    """Build PBXGroup entries for a directory tree."""
    groups = []
    all_dirs = sorted(children_map.keys())

    # Also add subdirectories that may not have files directly
    dir_set = set()
    for d in all_dirs:
        parts = d.split('/')
        for i in range(len(parts)):
            dir_set.add('/'.join(parts[:i+1]))
    all_dirs = sorted(dir_set)

    dir_to_group_id = {root_prefix: root_id}
    for d in all_dirs:
        if d not in dir_to_group_id:
            dir_to_group_id[d] = uid(d + '_group')

    for d in all_dirs:
        gid = dir_to_group_id[d]
        name = os.path.basename(d)
        path = name
        child_ids = []
        # Add subdirectory groups
        for d2 in all_dirs:
            parent = os.path.dirname(d2)
            if parent == d and d2 != d:
                child_ids.append(dir_to_group_id[d2])
        # Add file refs
        child_ids.extend(children_map.get(d, []))
        groups.append((gid, name, path, child_ids))

    # Root group
    root_child_ids = []
    for d in all_dirs:
        parent = os.path.dirname(d)
        if parent == '' or d == root_prefix:
            if d == root_prefix:
                root_child_ids.extend(children_map.get(d, []))
                # Add immediate subdirs
                for d2 in all_dirs:
                    if os.path.dirname(d2) == root_prefix and d2 != root_prefix:
                        root_child_ids.append(dir_to_group_id[d2])

    return groups, dir_to_group_id

app_groups, app_dir_map = build_groups(group_children_app, 'ClaudeLifter', APP_GROUP_ID, 'ClaudeLifter')
test_groups, test_dir_map = build_groups(group_children_test, 'ClaudeLifterTests', TEST_GROUP_ID, 'ClaudeLifterTests')

# Now write the project.pbxproj
lines = []
def w(s=''):
    lines.append(s)

w('// !$*UTF8*$!')
w('{')
w('\tarchiveVersion = 1;')
w('\tclasses = {')
w('\t};')
w('\tobjectVersion = 60;')
w('\tobjects = {')
w('')

# PBXBuildFile
w('/* Begin PBXBuildFile section */')
for build_id, ref_id, name in build_files_app:
    w(f'\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_id} /* {name} */; }};')
for build_id, ref_id, name in build_files_test:
    w(f'\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_id} /* {name} */; }};')
# Resources
w(f'\t\t{EXERCISES_JSON_BUILD_ID} /* exercises.json in Resources */ = {{isa = PBXBuildFile; fileRef = {EXERCISES_JSON_REF_ID} /* exercises.json */; }};')
w(f'\t\t{ASSETS_BUILD_ID} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ASSETS_REF_ID} /* Assets.xcassets */; }};')
w('/* End PBXBuildFile section */')
w('')

# PBXContainerItemProxy
w('/* Begin PBXContainerItemProxy section */')
w(f'\t\t{APP_DEP_PROXY_ID} /* PBXContainerItemProxy */ = {{')
w(f'\t\t\tisa = PBXContainerItemProxy;')
w(f'\t\t\tcontainerPortal = {PROJECT_ID} /* Project object */;')
w(f'\t\t\tproxyType = 1;')
w(f'\t\t\tremoteGlobalIDString = {APP_TARGET_ID};')
w(f'\t\t\tremoteInfo = ClaudeLifter;')
w(f'\t\t}};')
w('/* End PBXContainerItemProxy section */')
w('')

# PBXFileReference
w('/* Begin PBXFileReference section */')
w(f'\t\t{APP_PRODUCT_REF_ID} /* ClaudeLifter.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ClaudeLifter.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
w(f'\t\t{TEST_PRODUCT_REF_ID} /* ClaudeLifterTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ClaudeLifterTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};')
for ref_id, path, name in file_refs:
    w(f'\t\t{ref_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};')
w(f'\t\t{EXERCISES_JSON_REF_ID} /* exercises.json */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = exercises.json; sourceTree = "<group>"; }};')
w(f'\t\t{ASSETS_REF_ID} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};')
w('/* End PBXFileReference section */')
w('')

# PBXFrameworksBuildPhase
w('/* Begin PBXFrameworksBuildPhase section */')
w(f'\t\t{APP_FRAMEWORKS_PHASE_ID} /* Frameworks */ = {{')
w(f'\t\t\tisa = PBXFrameworksBuildPhase;')
w(f'\t\t\tbuildActionMask = 2147483647;')
w(f'\t\t\tfiles = (')
w(f'\t\t\t);')
w(f'\t\t\trunOnlyForDeploymentPostprocessing = 0;')
w(f'\t\t}};')
w(f'\t\t{TEST_FRAMEWORKS_PHASE_ID} /* Frameworks */ = {{')
w(f'\t\t\tisa = PBXFrameworksBuildPhase;')
w(f'\t\t\tbuildActionMask = 2147483647;')
w(f'\t\t\tfiles = (')
w(f'\t\t\t);')
w(f'\t\t\trunOnlyForDeploymentPostprocessing = 0;')
w(f'\t\t}};')
w('/* End PBXFrameworksBuildPhase section */')
w('')

# PBXGroup
w('/* Begin PBXGroup section */')

# Main group
app_top_children = []
# Get immediate subdirs of ClaudeLifter
for gid, name, path, children in app_groups:
    parent = None
    for g2id, g2name, g2path, g2children in app_groups:
        if gid in g2children:
            parent = g2id
    if parent is None and gid != APP_GROUP_ID:
        app_top_children.append(gid)

test_top_children = []
for gid, name, path, children in test_groups:
    parent = None
    for g2id, g2name, g2path, g2children in test_groups:
        if gid in g2children:
            parent = g2id
    if parent is None and gid != TEST_GROUP_ID:
        test_top_children.append(gid)

w(f'\t\t{MAIN_GROUP_ID} /* */ = {{')
w(f'\t\t\tisa = PBXGroup;')
w(f'\t\t\tchildren = (')
w(f'\t\t\t\t{APP_GROUP_ID} /* ClaudeLifter */,')
w(f'\t\t\t\t{TEST_GROUP_ID} /* ClaudeLifterTests */,')
w(f'\t\t\t\t{PRODUCTS_GROUP_ID} /* Products */,')
w(f'\t\t\t\t{FRAMEWORKS_GROUP_ID} /* Frameworks */,')
w(f'\t\t\t);')
w(f'\t\t\tsourceTree = "<group>";')
w(f'\t\t}};')

# Products group
w(f'\t\t{PRODUCTS_GROUP_ID} /* Products */ = {{')
w(f'\t\t\tisa = PBXGroup;')
w(f'\t\t\tchildren = (')
w(f'\t\t\t\t{APP_PRODUCT_REF_ID} /* ClaudeLifter.app */,')
w(f'\t\t\t\t{TEST_PRODUCT_REF_ID} /* ClaudeLifterTests.xctest */,')
w(f'\t\t\t);')
w(f'\t\t\tname = Products;')
w(f'\t\t\tsourceTree = "<group>";')
w(f'\t\t}};')

# Frameworks group
w(f'\t\t{FRAMEWORKS_GROUP_ID} /* Frameworks */ = {{')
w(f'\t\t\tisa = PBXGroup;')
w(f'\t\t\tchildren = (')
w(f'\t\t\t);')
w(f'\t\t\tname = Frameworks;')
w(f'\t\t\tsourceTree = "<group>";')
w(f'\t\t}};')

# App groups
# First the root ClaudeLifter group
app_root_subdirs = set()
for d in sorted(group_children_app.keys()):
    parts = d.replace('ClaudeLifter/', '').split('/')
    if len(parts) >= 1 and parts[0]:
        subdir = 'ClaudeLifter/' + parts[0]
        app_root_subdirs.add(subdir)

app_root_children = []
for sd in sorted(app_root_subdirs):
    if sd in app_dir_map:
        app_root_children.append(app_dir_map[sd])
# Also add direct files
app_root_children.extend(group_children_app.get('ClaudeLifter', []))
# Always include the Resources group
app_root_children.append(RESOURCES_GROUP_ID)

w(f'\t\t{APP_GROUP_ID} /* ClaudeLifter */ = {{')
w(f'\t\t\tisa = PBXGroup;')
w(f'\t\t\tchildren = (')
for cid in app_root_children:
    w(f'\t\t\t\t{cid},')
w(f'\t\t\t);')
w(f'\t\t\tpath = ClaudeLifter;')
w(f'\t\t\tsourceTree = "<group>";')
w(f'\t\t}};')

# Write all app subgroups
for gid, name, path, children in app_groups:
    if gid == APP_GROUP_ID:
        continue
    w(f'\t\t{gid} /* {name} */ = {{')
    w(f'\t\t\tisa = PBXGroup;')
    w(f'\t\t\tchildren = (')
    for cid in children:
        w(f'\t\t\t\t{cid},')
    w(f'\t\t\t);')
    w(f'\t\t\tpath = {path};')
    w(f'\t\t\tsourceTree = "<group>";')
    w(f'\t\t}};')

# Resources group (exercises.json, Assets.xcassets)
w(f'\t\t{RESOURCES_GROUP_ID} /* Resources */ = {{')
w(f'\t\t\tisa = PBXGroup;')
w(f'\t\t\tchildren = (')
w(f'\t\t\t\t{EXERCISES_JSON_REF_ID} /* exercises.json */,')
w(f'\t\t\t\t{ASSETS_REF_ID} /* Assets.xcassets */,')
w(f'\t\t\t);')
w(f'\t\t\tpath = Resources;')
w(f'\t\t\tsourceTree = "<group>";')
w(f'\t\t}};')

# Test groups - root
test_root_subdirs = set()
for d in sorted(group_children_test.keys()):
    parts = d.replace('ClaudeLifterTests/', '').split('/')
    if len(parts) >= 1 and parts[0]:
        subdir = 'ClaudeLifterTests/' + parts[0]
        test_root_subdirs.add(subdir)

test_root_children = []
for sd in sorted(test_root_subdirs):
    if sd in test_dir_map:
        test_root_children.append(test_dir_map[sd])
test_root_children.extend(group_children_test.get('ClaudeLifterTests', []))

w(f'\t\t{TEST_GROUP_ID} /* ClaudeLifterTests */ = {{')
w(f'\t\t\tisa = PBXGroup;')
w(f'\t\t\tchildren = (')
for cid in test_root_children:
    w(f'\t\t\t\t{cid},')
w(f'\t\t\t);')
w(f'\t\t\tpath = ClaudeLifterTests;')
w(f'\t\t\tsourceTree = "<group>";')
w(f'\t\t}};')

for gid, name, path, children in test_groups:
    if gid == TEST_GROUP_ID:
        continue
    w(f'\t\t{gid} /* {name} */ = {{')
    w(f'\t\t\tisa = PBXGroup;')
    w(f'\t\t\tchildren = (')
    for cid in children:
        w(f'\t\t\t\t{cid},')
    w(f'\t\t\t);')
    w(f'\t\t\tpath = {path};')
    w(f'\t\t\tsourceTree = "<group>";')
    w(f'\t\t}};')

w('/* End PBXGroup section */')
w('')

# PBXNativeTarget
w('/* Begin PBXNativeTarget section */')
w(f'\t\t{APP_TARGET_ID} /* ClaudeLifter */ = {{')
w(f'\t\t\tisa = PBXNativeTarget;')
w(f'\t\t\tbuildConfigurationList = {APP_BUILD_CONFIG_LIST_ID};')
w(f'\t\t\tbuildPhases = (')
w(f'\t\t\t\t{APP_SOURCES_PHASE_ID} /* Sources */,')
w(f'\t\t\t\t{APP_FRAMEWORKS_PHASE_ID} /* Frameworks */,')
w(f'\t\t\t\t{APP_RESOURCES_PHASE_ID} /* Resources */,')
w(f'\t\t\t);')
w(f'\t\t\tbuildRules = (')
w(f'\t\t\t);')
w(f'\t\t\tdependencies = (')
w(f'\t\t\t);')
w(f'\t\t\tname = ClaudeLifter;')
w(f'\t\t\tpackageProductDependencies = (')
w(f'\t\t\t\t{PACKAGE_PRODUCT_DEP_ID} /* SwiftAnthropic */,')
w(f'\t\t\t);')
w(f'\t\t\tproductName = ClaudeLifter;')
w(f'\t\t\tproductReference = {APP_PRODUCT_REF_ID} /* ClaudeLifter.app */;')
w(f'\t\t\tproductType = "com.apple.product-type.application";')
w(f'\t\t}};')

w(f'\t\t{TEST_TARGET_ID} /* ClaudeLifterTests */ = {{')
w(f'\t\t\tisa = PBXNativeTarget;')
w(f'\t\t\tbuildConfigurationList = {TEST_BUILD_CONFIG_LIST_ID};')
w(f'\t\t\tbuildPhases = (')
w(f'\t\t\t\t{TEST_SOURCES_PHASE_ID} /* Sources */,')
w(f'\t\t\t\t{TEST_FRAMEWORKS_PHASE_ID} /* Frameworks */,')
w(f'\t\t\t);')
w(f'\t\t\tbuildRules = (')
w(f'\t\t\t);')
w(f'\t\t\tdependencies = (')
w(f'\t\t\t\t{APP_DEP_ID} /* PBXTargetDependency */,')
w(f'\t\t\t);')
w(f'\t\t\tname = ClaudeLifterTests;')
w(f'\t\t\tproductName = ClaudeLifterTests;')
w(f'\t\t\tproductReference = {TEST_PRODUCT_REF_ID} /* ClaudeLifterTests.xctest */;')
w(f'\t\t\tproductType = "com.apple.product-type.bundle.unit-test";')
w(f'\t\t}};')
w('/* End PBXNativeTarget section */')
w('')

# PBXProject
w('/* Begin PBXProject section */')
w(f'\t\t{PROJECT_ID} /* Project object */ = {{')
w(f'\t\t\tisa = PBXProject;')
w(f'\t\t\tattributes = {{')
w(f'\t\t\t\tBuildIndependentTargetsInParallel = 1;')
w(f'\t\t\t\tLastSwiftUpdateCheck = 1600;')
w(f'\t\t\t\tLastUpgradeCheck = 1600;')
w(f'\t\t\t}};')
w(f'\t\t\tbuildConfigurationList = {PROJECT_BUILD_CONFIG_LIST_ID};')
w(f'\t\t\tcompatibilityVersion = "Xcode 14.0";')
w(f'\t\t\tdevelopmentRegion = en;')
w(f'\t\t\thasScannedForEncodings = 0;')
w(f'\t\t\tknownRegions = (')
w(f'\t\t\t\ten,')
w(f'\t\t\t\tBase,')
w(f'\t\t\t);')
w(f'\t\t\tmainGroup = {MAIN_GROUP_ID};')
w(f'\t\t\tpackageReferences = (')
w(f'\t\t\t\t{PACKAGE_REF_ID} /* XCRemoteSwiftPackageReference "SwiftAnthropic" */,')
w(f'\t\t\t);')
w(f'\t\t\tproductRefGroup = {PRODUCTS_GROUP_ID} /* Products */;')
w(f'\t\t\tprojectDirPath = "";')
w(f'\t\t\tprojectRoot = "";')
w(f'\t\t\ttargets = (')
w(f'\t\t\t\t{APP_TARGET_ID} /* ClaudeLifter */,')
w(f'\t\t\t\t{TEST_TARGET_ID} /* ClaudeLifterTests */,')
w(f'\t\t\t);')
w(f'\t\t}};')
w('/* End PBXProject section */')
w('')

# PBXResourcesBuildPhase
w('/* Begin PBXResourcesBuildPhase section */')
w(f'\t\t{APP_RESOURCES_PHASE_ID} /* Resources */ = {{')
w(f'\t\t\tisa = PBXResourcesBuildPhase;')
w(f'\t\t\tbuildActionMask = 2147483647;')
w(f'\t\t\tfiles = (')
w(f'\t\t\t\t{EXERCISES_JSON_BUILD_ID} /* exercises.json in Resources */,')
w(f'\t\t\t\t{ASSETS_BUILD_ID} /* Assets.xcassets in Resources */,')
w(f'\t\t\t);')
w(f'\t\t\trunOnlyForDeploymentPostprocessing = 0;')
w(f'\t\t}};')
w('/* End PBXResourcesBuildPhase section */')
w('')

# PBXSourcesBuildPhase
w('/* Begin PBXSourcesBuildPhase section */')
w(f'\t\t{APP_SOURCES_PHASE_ID} /* Sources */ = {{')
w(f'\t\t\tisa = PBXSourcesBuildPhase;')
w(f'\t\t\tbuildActionMask = 2147483647;')
w(f'\t\t\tfiles = (')
for build_id, ref_id, name in build_files_app:
    w(f'\t\t\t\t{build_id} /* {name} in Sources */,')
w(f'\t\t\t);')
w(f'\t\t\trunOnlyForDeploymentPostprocessing = 0;')
w(f'\t\t}};')
w(f'\t\t{TEST_SOURCES_PHASE_ID} /* Sources */ = {{')
w(f'\t\t\tisa = PBXSourcesBuildPhase;')
w(f'\t\t\tbuildActionMask = 2147483647;')
w(f'\t\t\tfiles = (')
for build_id, ref_id, name in build_files_test:
    w(f'\t\t\t\t{build_id} /* {name} in Sources */,')
w(f'\t\t\t);')
w(f'\t\t\trunOnlyForDeploymentPostprocessing = 0;')
w(f'\t\t}};')
w('/* End PBXSourcesBuildPhase section */')
w('')

# PBXTargetDependency
w('/* Begin PBXTargetDependency section */')
w(f'\t\t{APP_DEP_ID} /* PBXTargetDependency */ = {{')
w(f'\t\t\tisa = PBXTargetDependency;')
w(f'\t\t\ttarget = {APP_TARGET_ID} /* ClaudeLifter */;')
w(f'\t\t\ttargetProxy = {APP_DEP_PROXY_ID} /* PBXContainerItemProxy */;')
w(f'\t\t}};')
w('/* End PBXTargetDependency section */')
w('')

# XCBuildConfiguration
common_debug = {
    'ALWAYS_SEARCH_USER_PATHS': 'NO',
    'CLANG_ANALYZER_NONNULL': 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD': '"gnu++20"',
    'CLANG_ENABLE_MODULES': 'YES',
    'CLANG_ENABLE_OBJC_ARC': 'YES',
    'COPY_PHASE_STRIP': 'NO',
    'DEBUG_INFORMATION_FORMAT': '"dwarf-with-dsym"',
    'ENABLE_STRICT_OBJC_MSGSEND': 'YES',
    'ENABLE_TESTABILITY': 'YES',
    'GCC_DYNAMIC_NO_PIC': 'NO',
    'GCC_NO_COMMON_BLOCKS': 'YES',
    'GCC_OPTIMIZATION_LEVEL': '0',
    'GCC_WARN_ABOUT_RETURN_TYPE': 'YES_ERROR',
    'GCC_WARN_UNDECLARED_SELECTOR': 'YES',
    'GCC_WARN_UNINITIALIZED_AUTOS': 'YES_AGGRESSIVE',
    'GCC_WARN_UNUSED_FUNCTION': 'YES',
    'GCC_WARN_UNUSED_VARIABLE': 'YES',
    'IPHONEOS_DEPLOYMENT_TARGET': '17.0',
    'MTL_ENABLE_DEBUG_INFO': 'INCLUDE_SOURCE',
    'ONLY_ACTIVE_ARCH': 'YES',
    'SDKROOT': 'iphoneos',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '"$(inherited) DEBUG"',
    'SWIFT_OPTIMIZATION_LEVEL': '"-Onone"',
    'SWIFT_STRICT_CONCURRENCY': 'targeted',
}

common_release = dict(common_debug)
common_release['COPY_PHASE_STRIP'] = 'NO'
common_release['DEBUG_INFORMATION_FORMAT'] = '"dwarf-with-dsym"'
common_release['ENABLE_NS_ASSERTIONS'] = 'NO'
common_release['GCC_OPTIMIZATION_LEVEL'] = 's'
common_release['SWIFT_OPTIMIZATION_LEVEL'] = '"-O"'
common_release['SWIFT_COMPILATION_MODE'] = 'wholemodule'
del common_release['MTL_ENABLE_DEBUG_INFO']
del common_release['ONLY_ACTIVE_ARCH']
common_release['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '"$(inherited)"'
common_release['ENABLE_TESTABILITY'] = 'NO'
common_release['VALIDATE_PRODUCT'] = 'YES'

app_settings = {
    'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
    'CODE_SIGN_STYLE': 'Automatic',
    'CURRENT_PROJECT_VERSION': '1',
    'GENERATE_INFOPLIST_FILE': 'YES',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation': 'YES',
    'INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents': 'YES',
    'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad': '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone': '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
    'MARKETING_VERSION': '1.0',
    'PRODUCT_BUNDLE_IDENTIFIER': 'com.eddelord.ClaudeLifter',
    'PRODUCT_NAME': '"$(TARGET_NAME)"',
    'SWIFT_EMIT_LOC_STRINGS': 'YES',
    'SWIFT_VERSION': '6.0',
    'TARGETED_DEVICE_FAMILY': '"1,2"',
}

test_settings = {
    'BUNDLE_LOADER': '"$(TEST_HOST)"',
    'CODE_SIGN_STYLE': 'Automatic',
    'CURRENT_PROJECT_VERSION': '1',
    'GENERATE_INFOPLIST_FILE': 'YES',
    'MARKETING_VERSION': '1.0',
    'PRODUCT_BUNDLE_IDENTIFIER': 'com.eddelord.ClaudeLifterTests',
    'PRODUCT_NAME': '"$(TARGET_NAME)"',
    'SWIFT_EMIT_LOC_STRINGS': 'NO',
    'SWIFT_VERSION': '6.0',
    'TARGETED_DEVICE_FAMILY': '"1,2"',
    'TEST_HOST': '"$(BUILT_PRODUCTS_DIR)/ClaudeLifter.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ClaudeLifter"',
}

def write_config(config_id, name, settings):
    w(f'\t\t{config_id} /* {name} */ = {{')
    w(f'\t\t\tisa = XCBuildConfiguration;')
    w(f'\t\t\tbuildSettings = {{')
    for k, v in sorted(settings.items()):
        w(f'\t\t\t\t{k} = {v};')
    w(f'\t\t\t}};')
    w(f'\t\t\tname = {name};')
    w(f'\t\t}};')

w('/* Begin XCBuildConfiguration section */')
write_config(PROJECT_DEBUG_ID, 'Debug', common_debug)
write_config(PROJECT_RELEASE_ID, 'Release', common_release)
write_config(APP_DEBUG_ID, 'Debug', app_settings)
write_config(APP_RELEASE_ID, 'Release', app_settings)
write_config(TEST_DEBUG_ID, 'Debug', test_settings)
write_config(TEST_RELEASE_ID, 'Release', test_settings)
w('/* End XCBuildConfiguration section */')
w('')

# XCConfigurationList
w('/* Begin XCConfigurationList section */')
w(f'\t\t{PROJECT_BUILD_CONFIG_LIST_ID} /* Build configuration list for PBXProject "ClaudeLifter" */ = {{')
w(f'\t\t\tisa = XCConfigurationList;')
w(f'\t\t\tbuildConfigurations = (')
w(f'\t\t\t\t{PROJECT_DEBUG_ID} /* Debug */,')
w(f'\t\t\t\t{PROJECT_RELEASE_ID} /* Release */,')
w(f'\t\t\t);')
w(f'\t\t\tdefaultConfigurationIsVisible = 0;')
w(f'\t\t\tdefaultConfigurationName = Release;')
w(f'\t\t}};')
w(f'\t\t{APP_BUILD_CONFIG_LIST_ID} /* Build configuration list for PBXNativeTarget "ClaudeLifter" */ = {{')
w(f'\t\t\tisa = XCConfigurationList;')
w(f'\t\t\tbuildConfigurations = (')
w(f'\t\t\t\t{APP_DEBUG_ID} /* Debug */,')
w(f'\t\t\t\t{APP_RELEASE_ID} /* Release */,')
w(f'\t\t\t);')
w(f'\t\t\tdefaultConfigurationIsVisible = 0;')
w(f'\t\t\tdefaultConfigurationName = Release;')
w(f'\t\t}};')
w(f'\t\t{TEST_BUILD_CONFIG_LIST_ID} /* Build configuration list for PBXNativeTarget "ClaudeLifterTests" */ = {{')
w(f'\t\t\tisa = XCConfigurationList;')
w(f'\t\t\tbuildConfigurations = (')
w(f'\t\t\t\t{TEST_DEBUG_ID} /* Debug */,')
w(f'\t\t\t\t{TEST_RELEASE_ID} /* Release */,')
w(f'\t\t\t);')
w(f'\t\t\tdefaultConfigurationIsVisible = 0;')
w(f'\t\t\tdefaultConfigurationName = Release;')
w(f'\t\t}};')
w('/* End XCConfigurationList section */')
w('')

# XCRemoteSwiftPackageReference
w('/* Begin XCRemoteSwiftPackageReference section */')
w(f'\t\t{PACKAGE_REF_ID} /* XCRemoteSwiftPackageReference "SwiftAnthropic" */ = {{')
w(f'\t\t\tisa = XCRemoteSwiftPackageReference;')
w(f'\t\t\trepositoryURL = "https://github.com/jamesrochabrun/SwiftAnthropic";')
w(f'\t\t\trequirement = {{')
w(f'\t\t\t\tkind = upToNextMajorVersion;')
w(f'\t\t\t\tminimumVersion = 2.0.0;')
w(f'\t\t\t}};')
w(f'\t\t}};')
w('/* End XCRemoteSwiftPackageReference section */')
w('')

# XCSwiftPackageProductDependency
w('/* Begin XCSwiftPackageProductDependency section */')
w(f'\t\t{PACKAGE_PRODUCT_DEP_ID} /* SwiftAnthropic */ = {{')
w(f'\t\t\tisa = XCSwiftPackageProductDependency;')
w(f'\t\t\tpackage = {PACKAGE_REF_ID} /* XCRemoteSwiftPackageReference "SwiftAnthropic" */;')
w(f'\t\t\tproductName = SwiftAnthropic;')
w(f'\t\t}};')
w('/* End XCSwiftPackageProductDependency section */')
w('')

w('\t};')
w(f'\trootObject = {PROJECT_ID} /* Project object */;')
w('}')

with open('ClaudeLifter.xcodeproj/project.pbxproj', 'w') as f:
    f.write('\n'.join(lines) + '\n')

print(f"Generated project with {len(app_sources)} app sources and {len(test_sources)} test sources")
print(f"App groups: {len(app_groups)}, Test groups: {len(test_groups)}")
