#!/usr/bin/env python3
"""Generate RDPAirPlay.xcodeproj with a flat, valid group layout."""
import os
import platform
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = os.path.join(ROOT, "app")
SRC_ROOT = os.path.join(APP_DIR, "RDPAirPlay")
PROJECT_DIR = os.path.join(APP_DIR, "RDPAirPlay.xcodeproj")
SCHEME_DIR = os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes")

def uid():
    return uuid.uuid4().hex[:24].upper()

swift_files = []
for dirpath, _, filenames in os.walk(SRC_ROOT):
    for name in sorted(filenames):
        if name.endswith(".swift"):
            rel = os.path.relpath(os.path.join(dirpath, name), APP_DIR).replace("\\", "/")
            swift_files.append(rel)

native_sources = [
    "../native/src/rdp_bridge.c",
    "../native/src/rdp_bridge_freerdp.c",
]
all_sources = swift_files + native_sources

FREERDP_LIB_IOS = os.path.join(ROOT, "native", "dist", "freerdp", "lib", "iphoneos", "libfreerdp3.a")
FREERDP_LIB_SIM = os.path.join(ROOT, "native", "dist", "freerdp", "lib", "iphonesimulator", "libfreerdp3.a")
FREERDP_LIB_LEGACY = os.path.join(ROOT, "native", "dist", "freerdp", "lib", "libfreerdp3.a")
HAS_FREERDP = any(os.path.isfile(p) for p in (FREERDP_LIB_IOS, FREERDP_LIB_SIM, FREERDP_LIB_LEGACY))
HOST_ARCH = platform.machine()
SIM_EXCLUDED_ARCH = "arm64" if HOST_ARCH == "x86_64" else "x86_64"

# IDs
project_id = uid()
target_id = uid()
product_id = uid()
root_group = uid()
app_group = uid()
products_group = uid()
sources_phase = uid()
resources_phase = uid()
frameworks_phase = uid()
proj_config_list = uid()
target_config_list = uid()
proj_debug = uid()
proj_release = uid()
target_debug = uid()
target_release = uid()
assets_ref = uid()
assets_build = uid()

file_ref = {p: uid() for p in all_sources}
build_file = {p: uid() for p in all_sources}

lines = []
lines.append("// !$*UTF8*$!")
lines.append("{")
lines.append("\tarchiveVersion = 1;")
lines.append("\tclasses = {};")
lines.append("\tobjectVersion = 56;")
lines.append("\tobjects = {")
lines.append("")
lines.append("/* Begin PBXBuildFile section */")
lines.append(f"\t\t{assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_ref} /* Assets.xcassets */; }};")
for path in all_sources:
    base = os.path.basename(path)
    lines.append(f"\t\t{build_file[path]} /* {base} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref[path]} /* {base} */; }};")
lines.append("/* End PBXBuildFile section */")
lines.append("")
lines.append("/* Begin PBXFileReference section */")
lines.append(f"\t\t{product_id} /* RDPAirPlay.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = RDPAirPlay.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
assets_path = "RDPAirPlay/Assets.xcassets"
lines.append(f"\t\t{assets_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = \"{assets_path}\"; sourceTree = SOURCE_ROOT; }};")
for path in all_sources:
    base = os.path.basename(path)
    ftype = "sourcecode.swift" if path.endswith(".swift") else "sourcecode.c.c"
    lines.append(f"\t\t{file_ref[path]} /* {base} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = \"{path}\"; sourceTree = SOURCE_ROOT; }};")
lines.append("/* End PBXFileReference section */")
lines.append("")
lines.append("/* Begin PBXFrameworksBuildPhase section */")
lines.append(f"\t\t{frameworks_phase} /* Frameworks */ = {{")
lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXFrameworksBuildPhase section */")
lines.append("")
lines.append("/* Begin PBXGroup section */")
lines.append(f"\t\t{products_group} /* Products */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{product_id} /* RDPAirPlay.app */,")
lines.append("\t\t\t);")
lines.append("\t\t\tname = Products;")
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")
children = [f"{assets_ref} /* Assets.xcassets */,"]
for path in all_sources:
    base = os.path.basename(path)
    children.append(f"\t\t\t\t{file_ref[path]} /* {base} */,")
lines.append(f"\t\t{app_group} /* RDPAirPlay */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.extend(children)
lines.append("\t\t\t);")
lines.append("\t\t\tname = RDPAirPlay;")
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")
lines.append(f"\t\t{root_group} = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{app_group} /* RDPAirPlay */,")
lines.append(f"\t\t\t\t{products_group} /* Products */,")
lines.append("\t\t\t);")
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")
lines.append("/* End PBXGroup section */")
lines.append("")
lines.append("/* Begin PBXNativeTarget section */")
lines.append(f"\t\t{target_id} /* RDPAirPlay */ = {{")
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append(f"\t\t\tbuildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget \"RDPAirPlay\" */;")
lines.append("\t\t\tbuildPhases = (")
lines.append(f"\t\t\t\t{sources_phase} /* Sources */,")
lines.append(f"\t\t\t\t{frameworks_phase} /* Frameworks */,")
lines.append(f"\t\t\t\t{resources_phase} /* Resources */,")
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = (")
lines.append("\t\t\t);")
lines.append("\t\t\tdependencies = (")
lines.append("\t\t\t);")
lines.append("\t\t\tname = RDPAirPlay;")
lines.append("\t\t\tproductName = RDPAirPlay;")
lines.append(f"\t\t\tproductReference = {product_id} /* RDPAirPlay.app */;")
lines.append("\t\t\tproductType = \"com.apple.product-type.application\";")
lines.append("\t\t};")
lines.append("/* End PBXNativeTarget section */")
lines.append("")
lines.append("/* Begin PBXProject section */")
lines.append(f"\t\t{project_id} /* Project object */ = {{")
lines.append("\t\t\tisa = PBXProject;")
lines.append("\t\t\tattributes = {")
lines.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
lines.append("\t\t\t\tLastSwiftUpdateCheck = 1500;")
lines.append("\t\t\t\tLastUpgradeCheck = 1500;")
lines.append("\t\t\t};")
lines.append(f"\t\t\tbuildConfigurationList = {proj_config_list} /* Build configuration list for PBXProject \"RDPAirPlay\" */;")
lines.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
lines.append("\t\t\tdevelopmentRegion = \"zh-Hans\";")
lines.append("\t\t\thasScannedForEncodings = 0;")
lines.append("\t\t\tknownRegions = (")
lines.append("\t\t\t\ten,")
lines.append("\t\t\t\tBase,")
lines.append("\t\t\t\t\"zh-Hans\",")
lines.append("\t\t\t);")
lines.append(f"\t\t\tmainGroup = {root_group};")
lines.append(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
lines.append("\t\t\tprojectDirPath = \"\";")
lines.append("\t\t\tprojectRoot = \"\";")
lines.append("\t\t\ttargets = (")
lines.append(f"\t\t\t\t{target_id} /* RDPAirPlay */,")
lines.append("\t\t\t);")
lines.append("\t\t};")
lines.append("/* End PBXProject section */")
lines.append("")
lines.append("/* Begin PBXResourcesBuildPhase section */")
lines.append(f"\t\t{resources_phase} /* Resources */ = {{")
lines.append("\t\t\tisa = PBXResourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
lines.append(f"\t\t\t\t{assets_build} /* Assets.xcassets in Resources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXResourcesBuildPhase section */")
lines.append("")
lines.append("/* Begin PBXSourcesBuildPhase section */")
lines.append(f"\t\t{sources_phase} /* Sources */ = {{")
lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for path in all_sources:
    base = os.path.basename(path)
    lines.append(f"\t\t\t\t{build_file[path]} /* {base} in Sources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXSourcesBuildPhase section */")
lines.append("")

target_settings = """
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tHEADER_SEARCH_PATHS = (
\t\t\t\t\t"$(SRCROOT)/../native/include",
"""

if HAS_FREERDP:
    target_settings += """
\t\t\t\t\t"$(SRCROOT)/../native/dist/freerdp/include",
\t\t\t\t\t"$(SRCROOT)/../native/dist/openssl/ios/include",
\t\t\t\t\t"$(SRCROOT)/../native/dist/openssl/iossimulator/include",
"""
else:
    target_settings += "\n"

target_settings += """\t\t\t\t);
\t\t\t\tINFOPLIST_FILE = RDPAirPlay/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
"""

if HAS_FREERDP:
    target_settings += f"""
\t\t\t\t"EXCLUDED_ARCHS[sdk=iphonesimulator*]" = "$(inherited) {SIM_EXCLUDED_ARCH}";
\t\t\t\t"LIBRARY_SEARCH_PATHS[sdk=iphoneos*]" = (
\t\t\t\t\t"$(SRCROOT)/../native/dist/freerdp/lib/iphoneos",
\t\t\t\t\t"$(SRCROOT)/../native/dist/openssl/ios/lib",
\t\t\t\t);
\t\t\t\t"LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*]" = (
\t\t\t\t\t"$(SRCROOT)/../native/dist/freerdp/lib/iphonesimulator",
\t\t\t\t\t"$(SRCROOT)/../native/dist/openssl/iossimulator/lib",
\t\t\t\t);
\t\t\t\tOTHER_LDFLAGS = (
\t\t\t\t\t"-ObjC",
\t\t\t\t\t"-lfreerdp-client3",
\t\t\t\t\t"-lremdesk-client",
\t\t\t\t\t"-lremdesk-common",
\t\t\t\t\t"-lrdpsnd-common",
\t\t\t\t\t"-lfreerdp3",
\t\t\t\t\t"-lfreerdp-codecs",
\t\t\t\t\t"-lfreerdp-primitives",
\t\t\t\t\t"-lwinpr3",
\t\t\t\t\t"-lssl",
\t\t\t\t\t"-lcrypto",
\t\t\t\t\t"-lz",
\t\t\t\t\t"-framework",
\t\t\t\t\tAVFoundation,
\t\t\t\t\t"-framework",
\t\t\t\t\tCoreAudio,
\t\t\t\t\t"-framework",
\t\t\t\t\tAudioToolbox,
\t\t\t\t\t"-framework",
\t\t\t\t\tCoreGraphics,
\t\t\t\t\t"-framework",
\t\t\t\t\tFoundation,
\t\t\t\t\t"-framework",
\t\t\t\t\tUIKit,
\t\t\t\t\t"-framework",
\t\t\t\t\tGameController,
\t\t\t\t);
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"RDP_BRIDGE_HAS_FREERDP=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
"""

target_settings += """
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.rdpairplay.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "RDPAirPlay/RDPAirPlay-Bridging-Header.h";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
"""

lines.append("/* Begin XCBuildConfiguration section */")
lines.append(f"\t\t{proj_debug} /* Debug */ = {{")
lines.append("\t\t\tisa = XCBuildConfiguration;")
lines.append("\t\t\tbuildSettings = {")
lines.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
lines.append("\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
lines.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
lines.append("\t\t\t\tCOPY_PHASE_STRIP = NO;")
lines.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
lines.append("\t\t\t\tENABLE_TESTABILITY = YES;")
lines.append("\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;")
lines.append("\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
lines.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;")
lines.append("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
lines.append("\t\t\t\tSDKROOT = iphoneos;")
lines.append("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
lines.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
lines.append("\t\t\t};")
lines.append("\t\t\tname = Debug;")
lines.append("\t\t};")
lines.append(f"\t\t{proj_release} /* Release */ = {{")
lines.append("\t\t\tisa = XCBuildConfiguration;")
lines.append("\t\t\tbuildSettings = {")
lines.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
lines.append("\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
lines.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
lines.append("\t\t\t\tCOPY_PHASE_STRIP = NO;")
lines.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
lines.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;")
lines.append("\t\t\t\tSDKROOT = iphoneos;")
lines.append("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
lines.append("\t\t\t\tVALIDATE_PRODUCT = YES;")
lines.append("\t\t\t};")
lines.append("\t\t\tname = Release;")
lines.append("\t\t};")
for cfg_id, name in [(target_debug, "Debug"), (target_release, "Release")]:
    lines.append(f"\t\t{cfg_id} /* {name} */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    lines.append(target_settings)
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t};")
lines.append("/* End XCBuildConfiguration section */")
lines.append("")
lines.append("/* Begin XCConfigurationList section */")
lines.append(f"\t\t{proj_config_list} /* Build configuration list for PBXProject \"RDPAirPlay\" */ = {{")
lines.append("\t\t\tisa = XCConfigurationList;")
lines.append("\t\t\tbuildConfigurations = (")
lines.append(f"\t\t\t\t{proj_debug} /* Debug */,")
lines.append(f"\t\t\t\t{proj_release} /* Release */,")
lines.append("\t\t\t);")
lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
lines.append("\t\t\tdefaultConfigurationName = Release;")
lines.append("\t\t};")
lines.append(f"\t\t{target_config_list} /* Build configuration list for PBXNativeTarget \"RDPAirPlay\" */ = {{")
lines.append("\t\t\tisa = XCConfigurationList;")
lines.append("\t\t\tbuildConfigurations = (")
lines.append(f"\t\t\t\t{target_debug} /* Debug */,")
lines.append(f"\t\t\t\t{target_release} /* Release */,")
lines.append("\t\t\t);")
lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
lines.append("\t\t\tdefaultConfigurationName = Release;")
lines.append("\t\t};")
lines.append("/* End XCConfigurationList section */")
lines.append("\t};")
lines.append(f"\trootObject = {project_id} /* Project object */;")
lines.append("}")

os.makedirs(PROJECT_DIR, exist_ok=True)
os.makedirs(SCHEME_DIR, exist_ok=True)
with open(os.path.join(PROJECT_DIR, "project.pbxproj"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "RDPAirPlay.app"
               BlueprintName = "RDPAirPlay"
               ReferencedContainer = "container:RDPAirPlay.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "RDPAirPlay.app"
            BlueprintName = "RDPAirPlay"
            ReferencedContainer = "container:RDPAirPlay.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "RDPAirPlay.app"
            BlueprintName = "RDPAirPlay"
            ReferencedContainer = "container:RDPAirPlay.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
with open(os.path.join(SCHEME_DIR, "RDPAirPlay.xcscheme"), "w", encoding="utf-8") as f:
    f.write(scheme)

print(f"Generated {PROJECT_DIR}")
print(f"Sources: {len(all_sources)}")
print(f"FreeRDP linked: {HAS_FREERDP}")
