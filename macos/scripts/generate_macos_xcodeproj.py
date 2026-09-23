#!/usr/bin/env python3
"""Generate macos/MacRDP.xcodeproj for the macOS MacRDP target (separate from iOS)."""
import os
import platform
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # macos/
REPO = os.path.dirname(ROOT)
SRC_ROOT = os.path.join(ROOT, "MacRDP")
PROJECT_DIR = os.path.join(ROOT, "MacRDP.xcodeproj")
SCHEME_DIR = os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes")

def uid():
    return uuid.uuid4().hex[:24].upper()

swift_files = []
for dirpath, _, filenames in os.walk(SRC_ROOT):
    for name in sorted(filenames):
        if name.endswith(".swift"):
            rel = os.path.relpath(os.path.join(dirpath, name), ROOT).replace("\\", "/")
            swift_files.append(rel)

native_sources = [
    "../native/src/rdp_bridge.c",
    "../native/src/rdp_bridge_freerdp.c",
]
all_sources = swift_files + native_sources

FREERDP_PREFIX = os.path.join(REPO, "native", "dist", "freerdp-macos")
FREERDP_LIB = os.path.join(FREERDP_PREFIX, "lib", "libfreerdp3.dylib")
HAS_FREERDP = os.path.isfile(FREERDP_LIB) or os.path.isfile(
    os.path.join(FREERDP_PREFIX, "lib", "libfreerdp-client3.dylib")
)
HOST_ARCH = platform.machine()

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
bridging_ref = uid()

file_ref = {p: uid() for p in all_sources}
build_file = {p: uid() for p in all_sources}

frameworks = [
    ("AppKit.framework", "SDKROOT"),
    ("SwiftUI.framework", "SDKROOT"),
    ("Security.framework", "SDKROOT"),
    ("CoreGraphics.framework", "SDKROOT"),
]
fw_ref = {name: uid() for name, _ in frameworks}
fw_build = {name: uid() for name, _ in frameworks}

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
for name, _ in frameworks:
    lines.append(f"\t\t{fw_build[name]} /* {name} in Frameworks */ = {{isa = PBXBuildFile; fileRef = {fw_ref[name]} /* {name} */; }};")
lines.append("/* End PBXBuildFile section */")
lines.append("")
lines.append("/* Begin PBXFileReference section */")
lines.append(f"\t\t{product_id} /* MacRDP.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MacRDP.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
lines.append(f"\t\t{assets_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = MacRDP/Resources/Assets.xcassets; sourceTree = SOURCE_ROOT; }};")
lines.append(f"\t\t{bridging_ref} /* MacRDP-Bridging-Header.h */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = \"MacRDP/MacRDP-Bridging-Header.h\"; sourceTree = SOURCE_ROOT; }};")
for path in all_sources:
    base = os.path.basename(path)
    ftype = "sourcecode.swift" if path.endswith(".swift") else "sourcecode.c.c"
    lines.append(f"\t\t{file_ref[path]} /* {base} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = \"{path}\"; sourceTree = SOURCE_ROOT; }};")
for name, tree in frameworks:
    lines.append(f"\t\t{fw_ref[name]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = {name}; path = System/Library/Frameworks/{name}; sourceTree = {tree}; }};")
lines.append("/* End PBXFileReference section */")
lines.append("")
lines.append("/* Begin PBXFrameworksBuildPhase section */")
lines.append(f"\t\t{frameworks_phase} /* Frameworks */ = {{")
lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for name, _ in frameworks:
    lines.append(f"\t\t\t\t{fw_build[name]} /* {name} in Frameworks */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXFrameworksBuildPhase section */")
lines.append("")
lines.append("/* Begin PBXGroup section */")
lines.append(f"\t\t{root_group} = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{app_group} /* MacRDP */,")
lines.append(f"\t\t\t\t{products_group} /* Products */,")
lines.append("\t\t\t);")
lines.append('\t\t\tsourceTree = "<group>";')
lines.append("\t\t};")
lines.append(f"\t\t{app_group} /* MacRDP */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{assets_ref} /* Assets.xcassets */,")
lines.append(f"\t\t\t\t{bridging_ref} /* MacRDP-Bridging-Header.h */,")
for path in all_sources:
    lines.append(f"\t\t\t\t{file_ref[path]} /* {os.path.basename(path)} */,")
for name, _ in frameworks:
    lines.append(f"\t\t\t\t{fw_ref[name]} /* {name} */,")
lines.append("\t\t\t);")
lines.append('\t\t\tpath = "";')
lines.append('\t\t\tsourceTree = "<group>";')
lines.append("\t\t};")
lines.append(f"\t\t{products_group} /* Products */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{product_id} /* MacRDP.app */,")
lines.append("\t\t\t);")
lines.append("\t\t\tname = Products;")
lines.append('\t\t\tsourceTree = "<group>";')
lines.append("\t\t};")
lines.append("/* End PBXGroup section */")
lines.append("")
lines.append("/* Begin PBXNativeTarget section */")
lines.append(f"\t\t{target_id} /* MacRDP */ = {{")
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append('\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "MacRDP" */;' % target_config_list)
lines.append("\t\t\tbuildPhases = (")
lines.append(f"\t\t\t\t{sources_phase} /* Sources */,")
lines.append(f"\t\t\t\t{frameworks_phase} /* Frameworks */,")
lines.append(f"\t\t\t\t{resources_phase} /* Resources */,")
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = (")
lines.append("\t\t\t);")
lines.append("\t\t\tdependencies = (")
lines.append("\t\t\t);")
lines.append('\t\t\tname = MacRDP;')
lines.append('\t\t\tproductName = MacRDP;')
lines.append(f"\t\t\tproductReference = {product_id} /* MacRDP.app */;")
lines.append('\t\t\tproductType = "com.apple.product-type.application";')
lines.append("\t\t};")
lines.append("/* End PBXNativeTarget section */")
lines.append("")
lines.append("/* Begin PBXProject section */")
lines.append(f"\t\t{project_id} /* Project object */ = {{")
lines.append("\t\t\tisa = PBXProject;")
lines.append("\t\t\tattributes = {")
lines.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
lines.append('\t\t\t\tLastSwiftUpdateCheck = 1520;')
lines.append('\t\t\t\tLastUpgradeCheck = 1520;')
lines.append("\t\t\t};")
lines.append(f'\t\t\tbuildConfigurationList = {proj_config_list} /* Build configuration list for PBXProject "MacRDP" */;')
lines.append('\t\t\tcompatibilityVersion = "Xcode 14.0";')
lines.append("\t\t\tdevelopmentRegion = en;")
lines.append("\t\t\thasScannedForEncodings = 0;")
lines.append("\t\t\tknownRegions = (")
lines.append("\t\t\t\ten,")
lines.append("\t\t\t\tBase,")
lines.append("\t\t\t);")
lines.append(f"\t\t\tmainGroup = {root_group};")
lines.append(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
lines.append('\t\t\tprojectDirPath = "";')
lines.append('\t\t\tprojectRoot = "";')
lines.append("\t\t\ttargets = (")
lines.append(f"\t\t\t\t{target_id} /* MacRDP */,")
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
    lines.append(f"\t\t\t\t{build_file[path]} /* {os.path.basename(path)} in Sources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXSourcesBuildPhase section */")
lines.append("")

def xcconfig(is_debug, is_target):
    name = "Debug" if is_debug else "Release"
    out = []
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    if not is_target:
        out.append('\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;')
        out.append('\t\t\t\tCLANG_ENABLE_MODULES = YES;')
        out.append('\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;')
        out.append("\t\t\t\tCOPY_PHASE_STRIP = NO;")
        out.append(f'\t\t\t\tDEBUG_INFORMATION_FORMAT = "{"dwarf" if is_debug else "dwarf-with-dsym"}";')
        out.append(f"\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;" if is_debug else "\t\t\t\tGCC_DYNAMIC_NO_PIC = YES;")
        if is_debug:
            out.append("\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
            out.append("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
            out.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
            out.append("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
        out.append('\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;')
        out.append('\t\t\t\tSDKROOT = macosx;')
    else:
        gcc_flags = [
            "-I$(SRCROOT)/../native/include",
        ]
        if HAS_FREERDP:
            gcc_flags.append("-DRDP_BRIDGE_HAS_FREERDP=1")
            gcc_flags.append(f"-I{FREERDP_PREFIX}/include")
            gcc_flags.append(f"-I{FREERDP_PREFIX}/include/freerdp3")
            gcc_flags.append(f"-I{FREERDP_PREFIX}/include/winpr3")
        out.append('\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;')
        out.append('\t\t\t\tCODE_SIGN_STYLE = Automatic;')
        out.append('\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;')
        out.append('\t\t\t\tCURRENT_PROJECT_VERSION = 1;')
        out.append('\t\t\t\tENABLE_HARDENED_RUNTIME = NO;')
        out.append('\t\t\t\tGENERATE_INFOPLIST_FILE = YES;')
        out.append('\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = macrdp;')
        out.append('\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities";')
        out.append('\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";')
        out.append('\t\t\t\tINFOPLIST_KEY_NSPrincipalClass = NSApplication;')
        openssl_root = "/usr/local/opt/openssl@1.1"
        if not os.path.isdir(openssl_root):
            openssl_root = "/usr/local/opt/openssl@3"
        out.append('\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (')
        out.append('\t\t\t\t\t"$(inherited)",')
        out.append('\t\t\t\t\t"@executable_path/../Frameworks",')
        if HAS_FREERDP:
            out.append(f'\t\t\t\t\t"{FREERDP_PREFIX}/lib",')
            if os.path.isdir(openssl_root):
                out.append(f'\t\t\t\t\t"{openssl_root}/lib",')
        out.append("\t\t\t\t);")
        out.append('\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;')
        out.append('\t\t\t\tMARKETING_VERSION = 0.1.0;')
        out.append('\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.macrdp.app;')
        out.append('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
        out.append('\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;')
        out.append('\t\t\t\tSWIFT_VERSION = 5.0;')
        out.append('\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "MacRDP/MacRDP-Bridging-Header.h";')
        out.append("\t\t\t\tHEADER_SEARCH_PATHS = (")
        out.append('\t\t\t\t\t"$(SRCROOT)/../native/include",')
        if HAS_FREERDP:
            out.append(f'\t\t\t\t\t"{FREERDP_PREFIX}/include",')
            out.append(f'\t\t\t\t\t"{FREERDP_PREFIX}/include/freerdp3",')
            out.append(f'\t\t\t\t\t"{FREERDP_PREFIX}/include/winpr3",')
            if os.path.isdir(openssl_root):
                out.append(f'\t\t\t\t\t"{openssl_root}/include",')
        out.append("\t\t\t\t);")
        if HAS_FREERDP and os.path.isdir(openssl_root):
            gcc_flags.append(f"-I{openssl_root}/include")
        out.append('\t\t\t\tOTHER_CFLAGS = (')
        for flag in gcc_flags:
            out.append(f'\t\t\t\t\t"{flag}",')
        out.append("\t\t\t\t);")
        if HAS_FREERDP:
            out.append("\t\t\t\tLIBRARY_SEARCH_PATHS = (")
            out.append(f'\t\t\t\t\t"{FREERDP_PREFIX}/lib",')
            if os.path.isdir(openssl_root):
                out.append(f'\t\t\t\t\t"{openssl_root}/lib",')
            out.append("\t\t\t\t);")
            out.append("\t\t\t\tOTHER_LDFLAGS = (")
            out.append('\t\t\t\t\t"-lfreerdp3",')
            out.append('\t\t\t\t\t"-lfreerdp-client3",')
            out.append('\t\t\t\t\t"-lwinpr3",')
            out.append('\t\t\t\t\t"-lssl",')
            out.append('\t\t\t\t\t"-lcrypto",')
            out.append("\t\t\t\t);")
        # R1: Apple Silicon primary; Intel best-effort — build for host arch in Debug
        out.append(f'\t\t\t\tARCHS = "{HOST_ARCH}";')
        out.append('\t\t\t\tONLY_ACTIVE_ARCH = YES;')
    out.append("\t\t\t};")
    out.append(f'\t\t\tname = {name};')
    return out

lines.append("/* Begin XCBuildConfiguration section */")
lines.append(f"\t\t{proj_debug} /* Debug */ = {{")
lines.extend(xcconfig(True, False))
lines.append("\t\t};")
lines.append(f"\t\t{proj_release} /* Release */ = {{")
lines.extend(xcconfig(False, False))
lines.append("\t\t};")
lines.append(f"\t\t{target_debug} /* Debug */ = {{")
lines.extend(xcconfig(True, True))
lines.append("\t\t};")
lines.append(f"\t\t{target_release} /* Release */ = {{")
lines.extend(xcconfig(False, True))
lines.append("\t\t};")
lines.append("/* End XCBuildConfiguration section */")
lines.append("")
lines.append("/* Begin XCConfigurationList section */")
lines.append(f'\t\t{proj_config_list} /* Build configuration list for PBXProject "MacRDP" */ = {{')
lines.append("\t\t\tisa = XCConfigurationList;")
lines.append("\t\t\tbuildConfigurations = (")
lines.append(f"\t\t\t\t{proj_debug} /* Debug */,")
lines.append(f"\t\t\t\t{proj_release} /* Release */,")
lines.append("\t\t\t);")
lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
lines.append('\t\t\tdefaultConfigurationName = Release;')
lines.append("\t\t};")
lines.append(f'\t\t{target_config_list} /* Build configuration list for PBXNativeTarget "MacRDP" */ = {{')
lines.append("\t\t\tisa = XCConfigurationList;")
lines.append("\t\t\tbuildConfigurations = (")
lines.append(f"\t\t\t\t{target_debug} /* Debug */,")
lines.append(f"\t\t\t\t{target_release} /* Release */,")
lines.append("\t\t\t);")
lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
lines.append('\t\t\tdefaultConfigurationName = Release;')
lines.append("\t\t};")
lines.append("/* End XCConfigurationList section */")
lines.append("\t};")
lines.append(f"\trootObject = {project_id} /* Project object */;")
lines.append("}")

os.makedirs(PROJECT_DIR, exist_ok=True)
os.makedirs(SCHEME_DIR, exist_ok=True)
pbx = os.path.join(PROJECT_DIR, "project.pbxproj")
with open(pbx, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1520"
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
               BuildableName = "MacRDP.app"
               BlueprintName = "MacRDP"
               ReferencedContainer = "container:MacRDP.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
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
            BuildableName = "MacRDP.app"
            BlueprintName = "MacRDP"
            ReferencedContainer = "container:MacRDP.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
</Scheme>
"""
with open(os.path.join(SCHEME_DIR, "MacRDP.xcscheme"), "w", encoding="utf-8") as f:
    f.write(scheme)

print(f"Wrote {pbx}")
print(f"FreeRDP linked: {HAS_FREERDP} (arch={HOST_ARCH})")
print(f"Swift sources: {len(swift_files)}")
