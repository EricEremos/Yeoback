#!/usr/bin/env python3
import hashlib
import pathlib
import plistlib

ROOT = pathlib.Path(__file__).resolve().parent
objects = {}


def node(key, **fields):
    identifier = hashlib.sha256(key.encode()).hexdigest()[:24].upper()
    objects[identifier] = fields
    return identifier


def config_list(name, settings):
    values = []
    for mode in ("Debug", "Release"):
        local = dict(settings)
        local["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if mode == "Debug" else "-O"
        if mode == "Debug":
            local["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
            local["ENABLE_TESTABILITY"] = "YES"
        values.append(node(name + mode, isa="XCBuildConfiguration", name=mode, buildSettings=local))
    return node(name + "Configs", isa="XCConfigurationList", buildConfigurations=values,
                defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


products = []
references = []
targets = []
app_id = hashlib.sha256(b"AppTarget").hexdigest()[:24].upper()
for name, kind, sources in [
    ("Yeoback", "application", ["Yeoback/YeobackApp.swift", "Yeoback/FolderEngine.swift", "../../Sources/Cleanup/WorkArtifact.swift"]),
    ("YeobackTests", "bundle.unit-test", ["Tests/FolderEngineTests.swift"]),
    ("YeobackUITests", "bundle.ui-testing", ["UITests/YeobackUITests.swift"]),
]:
    builds = []
    resources = []
    for source in sources + (["Yeoback/Assets.xcassets"] if kind == "application" else []):
        asset = source.endswith("xcassets")
        ref = node(source, isa="PBXFileReference", path=source, sourceTree="<group>", lastKnownFileType="folder.assetcatalog" if asset else "sourcecode.swift")
        references.append(ref)
        build = node(source + "Build", isa="PBXBuildFile", fileRef=ref)
        (resources if asset else builds).append(build)
    product = node(name + "Product", isa="PBXFileReference", path=name + (".app" if kind == "application" else ".xctest"), sourceTree="BUILT_PRODUCTS_DIR", explicitFileType="wrapper.application" if kind == "application" else "wrapper.cfbundle")
    products.append(product)
    settings = {
        "PRODUCT_BUNDLE_IDENTIFIER": "app.yeoback.mobile" + ("" if kind == "application" else "." + name),
        "PRODUCT_NAME": "$(TARGET_NAME)", "SWIFT_VERSION": "5.0", "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "TARGETED_DEVICE_FAMILY": "1,2", "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_STYLE": "Automatic",
        "CODE_SIGNING_ALLOWED": "NO", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SDKROOT": "iphoneos",
    }
    if kind == "application":
        settings.update({"INFOPLIST_KEY_CFBundleDisplayName": "Yeoback", "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                         "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES", "MARKETING_VERSION": "0.1.0", "CURRENT_PROJECT_VERSION": "1",
                         "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"})
    elif kind == "bundle.unit-test":
        settings.update({"TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Yeoback.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Yeoback", "BUNDLE_LOADER": "$(TEST_HOST)"})
    else:
        settings["TEST_TARGET_NAME"] = "Yeoback"
    dependencies = [] if kind == "application" else [node(name + "Dependency", isa="PBXTargetDependency", target=app_id)]
    target = node("AppTarget" if kind == "application" else name + "Target", isa="PBXNativeTarget", name=name, productName=name,
        productReference=product, productType="com.apple.product-type." + kind, dependencies=dependencies,
        buildConfigurationList=config_list(name, settings), buildRules=[], buildPhases=[
            node(name + "Sources", isa="PBXSourcesBuildPhase", buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0),
            node(name + "Frameworks", isa="PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0),
            node(name + "Resources", isa="PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0),
        ])
    targets.append(target)
product_group = node("Products", isa="PBXGroup", children=products, name="Products", sourceTree="<group>")
main_group = node("Main", isa="PBXGroup", children=references + [product_group], sourceTree="<group>")
project = node("Project", isa="PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "2600"},
    buildConfigurationList=config_list("Project", {}), compatibilityVersion="Xcode 14.0", developmentRegion="en",
    knownRegions=["en", "Base"], mainGroup=main_group, productRefGroup=product_group, projectDirPath="", projectRoot="", targets=targets)
destination = ROOT / "Yeoback.xcodeproj"
destination.mkdir(exist_ok=True)
(destination / "project.pbxproj").write_bytes(plistlib.dumps({"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": objects, "rootObject": project}))
scheme = destination / "xcshareddata/xcschemes"
scheme.mkdir(parents=True, exist_ok=True)
def ref(target, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:Yeoback.xcodeproj"/>'
testables = "".join(f'<TestableReference skipped="NO">{ref(targets[i], name)}</TestableReference>' for i, name in [(1, "YeobackTests.xctest"), (2, "YeobackUITests.xctest")])
(scheme / "Yeoback.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref(app_id, "Yeoback.app")}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{testables}</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app_id, "Yeoback.app")}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app_id, "Yeoback.app")}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
