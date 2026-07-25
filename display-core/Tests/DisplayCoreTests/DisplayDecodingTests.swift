import Testing
import Foundation
@testable import DisplayCore

// Decode REAL /api/display responses captured from a running player (Fixtures/*.json). These lock the
// three item shapes (Library upload, Connected, Folder) and the top-level fields the app acts on.
@Suite struct DisplayDecodingTests {
    private func fixture(_ name: String) throws -> DisplayResponse {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name).json"
        )
        return try JSONDecoder().decode(DisplayResponse.self, from: Data(contentsOf: url))
    }

    @Test func decodesMixedLibraryRotation() throws {
        let r = try fixture("display-library")
        #expect(r.source == .library)
        #expect(r.mode == .sequence)
        #expect(r.pinnedId == nil)
        #expect(r.items.count == 4)
        #expect(r.items.map(\.id) == ["4", "5", "6", "7"]) // Int ids normalized to String
        #expect(r.items.map(\.kind) == [.connected, .video, .still, .animated])
        // the connected item's format "connected" is not a MediaFormat -> nil, and it is not renderable
        #expect(r.items[0].format == nil)
        #expect(r.items[0].isRenderable() == false)
        // still / video / animated ARE renderable; only the connected piece is skipped
        #expect(r.items[1].isRenderable()) // mp4
        #expect(r.items[2].isRenderable()) // png
        #expect(r.items[3].isRenderable()) // gif
        #expect(r.items.filter { $0.isRenderable() }.count == 3)
    }

    @Test func decodesPinnedConnected() throws {
        let r = try fixture("display-pinned-connected")
        #expect(r.pinnedId == "4")            // Int 4 -> "4"
        #expect(r.items.count == 1)
        #expect(r.items[0].kind == .connected)
        // §8: a pinned Connected piece is the whole rotation and cannot render -> the app shows splash,
        // never a substitute. Here "nothing renderable" is what produces that.
        #expect(r.items.allSatisfy { !$0.isRenderable() })
    }

    @Test func decodesFolderRotation() throws {
        let r = try fixture("display-folder")
        #expect(r.source == .folder)
        #expect(r.items.allSatisfy { $0.id.hasPrefix("fc") })              // String ids
        #expect(r.items.allSatisfy { $0.src?.hasPrefix("/folder-media/") == true })
        #expect(r.items.allSatisfy { $0.fit == .fill })
        #expect(r.items.allSatisfy { $0.isRenderable() })                  // all still/video
    }

    // A Host older than this app never sends `muted`; older/newer Hosts may drop or add fields. Decoding
    // must stay lenient and never choke (§11). Also checks SVG/WebM are declined by the filter.
    @Test func decodesLenientlyAcrossHostVersions() throws {
        let json = Data("""
        {"items":[
            {"id":9,"filename":"x.webm","format":"webm","kind":"video","fit":"fit"},
            {"id":10,"filename":"y.svg","format":"svg","kind":"animated","fit":"fill"},
            {"id":11,"filename":"z.jpg","format":"jpeg","kind":"still","fit":"fit","futureField":123}
        ],"durationMs":5000,"mode":"shuffle","pinnedId":null,"asleep":true,"source":"library"}
        """.utf8)
        let r = try JSONDecoder().decode(DisplayResponse.self, from: json)
        #expect(r.mode == .shuffle)
        #expect(r.asleep == true)
        #expect(r.items.count == 3)
        #expect(r.items[0].isRenderable() == false) // webm declined (§6)
        #expect(r.items[1].isRenderable() == false) // svg declined (§6)
        #expect(r.items[2].isRenderable() == true)  // jpeg renders; unknown futureField ignored
    }
}
