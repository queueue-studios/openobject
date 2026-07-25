// swift-tools-version: 6.0
import PackageDescription

// DisplayCore — the native (Swift) implementation of OpenObject's Display role, shared by the tvOS
// app and, later, the iPad app (docs/TVOS-APP-PLAN.md §7). No UI: it is discovery, the Host model,
// the /api/display client, the capability filter, the rotation engine (a port of
// player/public/display.js), and the media pipeline. It talks to a Host exactly as a browser display
// does, so the Host (player/server.js) and the XXL frame are unchanged (§3, §11).
//
// macOS is a supported platform ONLY so the whole engine unit-tests headlessly (`swift test`) with no
// app, device, or simulator; no macOS product ships from here (the Mac app drives real Chrome instead,
// MAC-APP-PLAN §5). tvOS 17 / iOS 17 is the floor: it covers every v1 format (still AVIF needs tvOS 16)
// and the modern APIs the app layer will use. The product version stays sourced from
// player/package.json (one repo, one version, MAC-APP-PLAN §3); a Swift package needs no version here.
let package = Package(
    name: "DisplayCore",
    platforms: [
        .tvOS(.v17),
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "DisplayCore", targets: ["DisplayCore"]),
    ],
    targets: [
        .target(name: "DisplayCore"),
        .testTarget(
            name: "DisplayCoreTests",
            dependencies: ["DisplayCore"],
            resources: [.copy("Fixtures")] // real /api/display captures, decoded in tests
        ),
    ]
)
