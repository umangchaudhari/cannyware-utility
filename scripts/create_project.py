"""Regenerate the dependency-free Xcode project. Uses only Python's standard library."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parent.parent
objects = {}
# Keep signing, team, version, and other settings edited by the project owner.
project_path = ROOT / "CannywareUtility.xcodeproj/project.pbxproj"
previous_objects = {}
if project_path.exists():
    previous = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project_path)]))
    previous_objects = previous.get("objects", {})


def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def add(name, value):
    objects[ident(name)] = value
    return ident(name)


def quoted(value):
    return json.dumps(str(value))


def plist(value, level=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (level + 1) + quoted(k) + " = " + plist(v, level + 1) + ";\n" for k, v in value.items()) + "\t" * level + "}"
    if isinstance(value, list):
        return "(" + ", ".join(plist(v, level) for v in value) + ")"
    return quoted(value)


products = []
groups = []
targets = []
for name, kind, bundle in [
    ("CannywareUtility", "application", "com.cannyware.photos"),
    ("CannywareUtilityTests", "bundle.unit-test", "com.cannyware.photos.tests"),
    ("CannywareUtilityUITests", "bundle.ui-testing", "com.cannyware.photos.uitests"),
]:
    app = kind == "application"
    ext = "app" if app else "xctest"
    product_name = "Cannyware Utility" if app else name
    product = add(name + "Product", {"isa": "PBXFileReference", "explicitFileType": "wrapper.application" if app else "wrapper.cfbundle", "path": f"{product_name}.{ext}", "sourceTree": "BUILT_PRODUCTS_DIR"})
    products.append(product)
    references, source_builds, resource_builds = [], [], []
    files = sorted((ROOT / name).rglob("*.swift"))
    if app:
        files += [ROOT / name / "Assets.xcassets", ROOT / name / "PrivacyInfo.xcprivacy", ROOT / name / "Info.plist"]
    for file in files:
        relative = str(file.relative_to(ROOT / name))
        filetype = {".swift": "sourcecode.swift", ".xcassets": "folder.assetcatalog", ".xcprivacy": "text.xml", ".plist": "text.plist.xml"}[file.suffix]
        reference = add(name + relative + "Ref", {"isa": "PBXFileReference", "lastKnownFileType": filetype, "path": relative, "sourceTree": "<group>"})
        references.append(reference)
        if file.name != "Info.plist":
            build = add(name + relative + "Build", {"isa": "PBXBuildFile", "fileRef": reference})
            (source_builds if file.suffix == ".swift" else resource_builds).append(build)
    groups.append(add(name + "Group", {"isa": "PBXGroup", "path": name, "sourceTree": "<group>", "children": references}))
    phases = []
    for phase, files in [("Sources", source_builds), ("Frameworks", []), ("Resources", resource_builds)]:
        phases.append(add(name + phase, {"isa": "PBX" + phase + "BuildPhase", "buildActionMask": "2147483647", "files": files, "runOnlyForDeploymentPostprocessing": "0"}))
    configs = []
    for config in ["Debug", "Release"]:
        settings = {
            "PRODUCT_BUNDLE_IDENTIFIER": bundle, "PRODUCT_NAME": product_name, "PRODUCT_MODULE_NAME": name,
            "TARGETED_DEVICE_FAMILY": "1,2", "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0",
            "GENERATE_INFOPLIST_FILE": "NO" if app else "YES",
            "SWIFT_EMIT_LOC_STRINGS": "YES", "SUPPORTS_MACCATALYST": "NO",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        }
        if app:
            settings.update({"INFOPLIST_FILE": "CannywareUtility/Info.plist", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor", "ENABLE_PREVIEWS": "YES"})
        elif kind == "bundle.unit-test":
            settings.update({"BUNDLE_LOADER": "$(TEST_HOST)", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Cannyware Utility.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Cannyware Utility"})
        else:
            settings["TEST_TARGET_NAME"] = "CannywareUtility"
        settings.update(previous_objects.get(ident(name + config), {}).get("buildSettings", {}))
        configs.append(add(name + config, {"isa": "XCBuildConfiguration", "name": config, "buildSettings": settings}))
    config_list = add(name + "Configs", {"isa": "XCConfigurationList", "buildConfigurations": configs, "defaultConfigurationIsVisible": "0", "defaultConfigurationName": "Release"})
    deps = []
    if not app:
        proxy = add(name + "Proxy", {"isa": "PBXContainerItemProxy", "containerPortal": ident("Project"), "proxyType": "1", "remoteGlobalIDString": ident("CannywareUtilityTarget"), "remoteInfo": "CannywareUtility"})
        deps.append(add(name + "Dependency", {"isa": "PBXTargetDependency", "target": ident("CannywareUtilityTarget"), "targetProxy": proxy}))
    targets.append(add(name + "Target", {"isa": "PBXNativeTarget", "name": name, "productName": product_name, "productReference": product, "productType": "com.apple.product-type." + kind, "buildConfigurationList": config_list, "buildPhases": phases, "buildRules": [], "dependencies": deps}))

groups.append(add("Products", {"isa": "PBXGroup", "name": "Products", "sourceTree": "<group>", "children": products}))
main = add("MainGroup", {"isa": "PBXGroup", "children": groups, "sourceTree": "<group>"})
configs = []
for config in ["Debug", "Release"]:
    settings = {
        "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0",
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17", "SWIFT_STRICT_CONCURRENCY": "complete",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else "dwarf-with-dsym",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)" if config == "Debug" else "$(inherited)",
        "ENABLE_TESTABILITY": "YES" if config == "Debug" else "NO",
        "ONLY_ACTIVE_ARCH": "YES" if config == "Debug" else "NO",
    }
    settings.update(previous_objects.get(ident("Project" + config), {}).get("buildSettings", {}))
    configs.append(add("Project" + config, {"isa": "XCBuildConfiguration", "name": config, "buildSettings": settings}))
configuration = add("ProjectConfigs", {"isa": "XCConfigurationList", "buildConfigurations": configs, "defaultConfigurationIsVisible": "0", "defaultConfigurationName": "Release"})
project = add("Project", {"isa": "PBXProject", "attributes": previous_objects.get(ident("Project"), {}).get("attributes", {"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "2700"}), "buildConfigurationList": configuration, "compatibilityVersion": "Xcode 14.0", "developmentRegion": "en", "knownRegions": ["en", "Base"], "mainGroup": main, "productRefGroup": ident("Products"), "projectDirPath": "", "projectRoot": "", "targets": targets})
(ROOT / "CannywareUtility.xcodeproj/project.pbxproj").write_text("// !$*UTF8*$!\n" + plist({"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": objects, "rootObject": project}) + "\n")

def buildable(name):
    ext = "app" if name == "CannywareUtility" else "xctest"
    product_name = "Cannyware Utility" if name == "CannywareUtility" else name
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(name + "Target")}" BuildableName="{product_name}.{ext}" BlueprintName="{name}" ReferencedContainer="container:CannywareUtility.xcodeproj"/>'

scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable("CannywareUtility")}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
  <TestableReference skipped="NO" parallelizable="NO">{buildable("CannywareUtilityTests")}</TestableReference>
  <TestableReference skipped="NO" parallelizable="NO">{buildable("CannywareUtilityUITests")}</TestableReference>
 </Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable("CannywareUtility")}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable("CannywareUtility")}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(ROOT / "CannywareUtility.xcodeproj/xcshareddata/xcschemes/Cannyware Utility.xcscheme").write_text(scheme)

palette = {
    "AccentColor": ("285544", "BCDFA7"), "Paper": ("F5F5EF", "161C18"),
    "Surface": ("FFFFFF", "222B24"), "Mint": ("E8EFD9", "354532"), "OnAccent": ("FFFFFF", "182C20"),
}
assets = ROOT / "CannywareUtility/Assets.xcassets"
(assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
for name, values in palette.items():
    colors = []
    for index, hex_color in enumerate(values):
        components = {key: f"{int(hex_color[offset:offset+2], 16) / 255:.4f}" for key, offset in [("red", 0), ("green", 2), ("blue", 4)]}
        components["alpha"] = "1.000"
        color = {"idiom": "universal", "color": {"color-space": "srgb", "components": components}}
        if index:
            color["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        colors.append(color)
    folder = assets / f"{name}.colorset"
    folder.mkdir(exist_ok=True)
    (folder / "Contents.json").write_text(json.dumps({"colors": colors, "info": {"author": "xcode", "version": 1}}, indent=2))
