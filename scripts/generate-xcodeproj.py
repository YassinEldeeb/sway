#!/usr/bin/env python3
"""Generates Xcode/Sway.xcodeproj: a macOS app target built from
Sources/SwayApp, linking the SwayCore library from the local Swift package
(Package.swift at the repo root), with the bundle's Info.plist, entitlements
and hardened runtime. Re-run after adding or removing app source files.

    python3 scripts/generate-xcodeproj.py
"""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Xcode", "Sway.xcodeproj")
APP_SOURCES = sorted(f for f in os.listdir(os.path.join(ROOT, "Sources", "SwayApp")) if f.endswith(".swift"))


def oid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


objects = []


def obj(name, body):
    objects.append((oid(name), body))
    return oid(name)


file_refs = {f: obj("ref:" + f, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{f}"; sourceTree = "<group>"; }}') for f in APP_SOURCES}
build_files = {f: obj("build:" + f, f"{{isa = PBXBuildFile; fileRef = {file_refs[f]} /* {f} */; }}") for f in APP_SOURCES}
info_ref = obj("ref:Info.plist", '{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }')
ent_ref = obj("ref:entitlements", '{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Sway.entitlements; sourceTree = "<group>"; }')
product_ref = obj("ref:product", "{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Sway.app; sourceTree = BUILT_PRODUCTS_DIR; }")

package_ref = obj("package", '{isa = XCLocalSwiftPackageReference; relativePath = ..; }')
core_dep = obj("dep:SwayCore", f"{{isa = XCSwiftPackageProductDependency; package = {package_ref}; productName = SwayCore; }}")
core_build = obj("build:SwayCore", f"{{isa = PBXBuildFile; productRef = {core_dep} /* SwayCore */; }}")

app_group = obj("group:app", "{isa = PBXGroup; children = (" + ", ".join(file_refs[f] for f in APP_SOURCES) + '); name = SwayApp; path = ../Sources/SwayApp; sourceTree = "<group>"; }')
res_group = obj("group:res", f'{{isa = PBXGroup; children = ({info_ref}, {ent_ref}); name = Resources; path = ../Resources; sourceTree = "<group>"; }}')
products_group = obj("group:products", f'{{isa = PBXGroup; children = ({product_ref}); name = Products; sourceTree = "<group>"; }}')
main_group = obj("group:main", f'{{isa = PBXGroup; children = ({app_group}, {res_group}, {products_group}); sourceTree = "<group>"; }}')

sources_phase = obj("phase:sources", "{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (" + ", ".join(build_files[f] for f in APP_SOURCES) + "); runOnlyForDeploymentPostprocessing = 0; }")
frameworks_phase = obj("phase:frameworks", f"{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({core_build}); runOnlyForDeploymentPostprocessing = 0; }}")
resources_phase = obj("phase:resources", "{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }")

common_target = {
    "PRODUCT_NAME": "Sway",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.sway.coach",
    "INFOPLIST_FILE": "../Resources/Info.plist",
    "GENERATE_INFOPLIST_FILE": "NO",
    "CODE_SIGN_ENTITLEMENTS": "../Resources/Sway.entitlements",
    "CODE_SIGN_IDENTITY": '"-"',
    "CODE_SIGN_STYLE": "Manual",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "SWIFT_VERSION": "5.0",
    "LD_RUNPATH_SEARCH_PATHS": '"@executable_path/../Frameworks"',
    "COMBINE_HIDPI_IMAGES": "YES",
}
common_project = {
    "SDKROOT": "macosx",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
}


def settings(d):
    return "{" + " ".join(f"{k} = {v};" for k, v in sorted(d.items())) + "}"


def config(name, kind, extra):
    return obj(f"config:{kind}:{name}", f"{{isa = XCBuildConfiguration; buildSettings = {settings(extra)}; name = {name}; }}")


t_debug = config("Debug", "target", {**common_target, "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"', "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"})
t_release = config("Release", "target", {**common_target, "SWIFT_OPTIMIZATION_LEVEL": '"-O"', "SWIFT_COMPILATION_MODE": "wholemodule"})
p_debug = config("Debug", "project", {**common_project, "ONLY_ACTIVE_ARCH": "YES", "DEBUG_INFORMATION_FORMAT": "dwarf"})
p_release = config("Release", "project", {**common_project, "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"'})
t_list = obj("list:target", f"{{isa = XCConfigurationList; buildConfigurations = ({t_debug}, {t_release}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}")
p_list = obj("list:project", f"{{isa = XCConfigurationList; buildConfigurations = ({p_debug}, {p_release}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}")

target = obj("target:Sway", f"{{isa = PBXNativeTarget; buildConfigurationList = {t_list}; buildPhases = ({sources_phase}, {frameworks_phase}, {resources_phase}); buildRules = (); dependencies = (); name = Sway; packageProductDependencies = ({core_dep}); productName = Sway; productReference = {product_ref}; productType = \"com.apple.product-type.application\"; }}")
project = obj("project", f"{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1500; LastUpgradeCheck = 1500; }}; buildConfigurationList = {p_list}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main_group}; packageReferences = ({package_ref}); productRefGroup = {products_group}; projectDirPath = \"\"; projectRoot = \"\"; targets = ({target}); }}")

os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "project.pbxproj"), "w") as f:
    f.write("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 60;\n\tobjects = {\n")
    for i, body in sorted(objects):
        f.write(f"\t\t{i} = {body};\n")
    f.write(f"\t}};\n\trootObject = {project};\n}}\n")
print(f"Wrote {OUT} ({len(APP_SOURCES)} app sources)")
