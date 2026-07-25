// DisplayCore — the native implementation of OpenObject's Display role.
//
// OpenObject has one engine and three roles (HANDOFF §20; MAC-APP-PLAN §2): Host, Display, Control.
// Every display today is a web page; the Apple TV cannot be one (tvOS has no web view), so this
// package reimplements the DISPLAY ROLE natively: discovery, the Host model and default Host, the
// /api/display client, the capability filter, the rotation engine (a faithful port of
// player/public/display.js), and a memory-safe media pipeline. It is shared by the tvOS app and,
// later, the iPad app, so both stay identical to each other and faithful to the frame.
//
// Deliberately UI-free and Host-neutral: it renders exactly one Host's rotation and talks to that
// Host exactly as a browser display does. The Host (player/server.js) gets no tvOS-specific endpoint
// and no per-client logic, and the XXL frame is untouched (docs/TVOS-APP-PLAN.md §3, §11, §15).

/// Namespace marker for the DisplayCore module. The real types live in their own files
/// (Host, CapabilityFilter, the rotation engine, …) as the phase fills in.
public enum DisplayCore {
    /// Module identifier. The single source of truth for the *product* version is
    /// `player/package.json` (MAC-APP-PLAN §3); this is only a package-level marker.
    public static let moduleName = "DisplayCore"
}
