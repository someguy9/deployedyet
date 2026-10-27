import ProjectDescription

let project = Project(
    name: "DeployedYet",
    targets: [
        .target(
            name: "DeployedYet",
            destinations: .macOS,
            product: .app,
            bundleId: "com.deployedyet.app",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": true,
                "LSApplicationCategoryType": "public.app-category.developer-tools",
                "CFBundleDisplayName": "Deployed Yet?",
                "CFBundleShortVersionString": "0.1.1",
                "CFBundleVersion": "2",
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            settings: .settings(base: [
                "SWIFT_VERSION": "6.0",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "", // use the system accent
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                // Stable signature so Keychain doesn't re-prompt after every rebuild.
                "DEVELOPMENT_TEAM": "WX67M3Z25T",
                "CODE_SIGN_STYLE": "Manual",
                "CODE_SIGN_IDENTITY": "Apple Development",
                // Blocks injected libraries reading tokens through the app; notarization requires it anyway.
                "ENABLE_HARDENED_RUNTIME": "YES",
            ])
        ),
    ]
)
