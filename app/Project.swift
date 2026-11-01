import ProjectDescription

let project = Project(
    name: "DeployedYet",
    packages: [
        .remote(url: "https://github.com/sparkle-project/Sparkle", requirement: .upToNextMajor(from: "2.10.1")),
    ],
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
                "CFBundleShortVersionString": "0.1.9",
                "CFBundleVersion": "10", // Sparkle compares this one: bump it every release
                // Updates: Sparkle reads the appcast attached to the newest GitHub release (release.sh makes it).
                "SUFeedURL": "https://github.com/someguy9/deployedyet/releases/latest/download/appcast.xml",
                "SUPublicEDKey": "i8vRR31daZXNtM/cs9W+/X0GG+L56WXwrsHIV+2hAJc=", // private half: login Keychain, account "deployedyet"
                "SUEnableAutomaticChecks": true, // on by default, no "check automatically?" prompt
                "SUAutomaticallyUpdate": true,
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            dependencies: [.package(product: "Sparkle")],
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
