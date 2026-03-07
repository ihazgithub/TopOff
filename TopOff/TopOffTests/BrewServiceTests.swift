import XCTest
@testable import TopOff

@MainActor
final class BrewServiceTests: XCTestCase {

    func testBrewPathExists() {
        let service = BrewService()
        XCTAssertNotNil(service.brewPath, "Brew path should be found")
    }

    func testFindBrewPathAppleSilicon() {
        let service = BrewService()
        let path = service.findBrewPath()
        // Should find either Apple Silicon or Intel path
        XCTAssertTrue(
            path == "/opt/homebrew/bin/brew" || path == "/usr/local/bin/brew",
            "Should find valid brew path"
        )
    }

    func testPermissionErrorDetectionForSudoPromptFailures() {
        let service = BrewService()
        XCTAssertTrue(
            service.isPermissionError("sudo: a terminal is required to read the password"),
            "Should detect non-TTY sudo prompt failures as permission errors"
        )
    }
}
