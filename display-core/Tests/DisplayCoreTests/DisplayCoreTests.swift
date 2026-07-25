import Testing
@testable import DisplayCore

// Scaffold smoke test: proves the package builds, the module imports, and `swift test` runs. Real
// coverage (Host model, capability filter, rotation engine, decoding) arrives with each component.
@Test func moduleImports() {
    #expect(DisplayCore.moduleName == "DisplayCore")
}
