// swift-tools-version: 5.9
import PackageDescription

// DisplayUI — the shared native UI for OpenObject's Display role: the input-agnostic pieces of the
// art stage that the tvOS and iPad apps both render (docs/TVOS-APP-PLAN.md §7). It sits on top of
// DisplayCore (the headless engine) and holds no Siri Remote / touch / focus logic itself; each app
// wraps ArtStageCore and adds its own input (the Host picker, the exit affordance) around it.
//
// It is a SEPARATE package from display-core (not a second target) on purpose: these views import
// UIKit, which does not exist on macOS, and display-core keeps a macOS platform so the whole engine
// unit-tests headlessly (`swift test`). So the UI layer is tvOS + iOS only. Swift 5 language mode
// (tools 5.9) matches how these views were written and verified in the tvOS app; DisplayCore stays
// in its own Swift 6 mode. Consumed as a local package by tv-app and ipad-app.
let package = Package(
    name: "DisplayUI",
    platforms: [
        .tvOS(.v17),
        .iOS(.v17),
    ],
    products: [
        .library(name: "DisplayUI", targets: ["DisplayUI"]),
    ],
    dependencies: [
        .package(path: "../display-core"),
    ],
    targets: [
        .target(
            name: "DisplayUI",
            dependencies: [.product(name: "DisplayCore", package: "display-core")]
        ),
    ]
)
