#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif
import Dispatch
import Foundation
import Logging
@testable import RepoPromptMCP
import XCTest

final class NewlineDelimitedSocketReaderTests: XCTestCase {
    func testReadBasicFrames() throws {
        var sockets = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer {
            if sockets[0] >= 0 { close(sockets[0]) }
            if sockets[1] >= 0 { close(sockets[1]) }
        }

        let flags = fcntl(sockets[0], F_GETFL)
        XCTAssertEqual(fcntl(sockets[0], F_SETFL, flags | O_NONBLOCK), 0)

        let queue = DispatchQueue(label: "NewlineDelimitedSocketReaderTests")
        var frames: [String] = []
        let eofDelivered = expectation(description: "EOF delivered")

        let reader = NewlineDelimitedSocketReader(
            fd: sockets[0],
            queue: queue,
            logger: Logger(label: "NewlineDelimitedSocketReaderTests"),
            onFrame: { frame in
                frames.append(String(decoding: frame, as: UTF8.self))
            },
            onEOF: { hasResidualData in
                XCTAssertFalse(hasResidualData)
                eofDelivered.fulfill()
            },
            onError: { XCTFail("Unexpected error: \($0)") }
        )

        try reader.start()

        let payload = Data("frame1\nframe2\n".utf8)
        let written = payload.withUnsafeBytes { bytes in
            write(sockets[1], bytes.baseAddress, bytes.count)
        }
        XCTAssertEqual(written, payload.count)

        XCTAssertEqual(shutdown(sockets[1], SHUT_WR), 0)
        wait(for: [eofDelivered], timeout: 1)

        XCTAssertEqual(frames, ["frame1", "frame2"])
    }

    func testCustomDelimiter() throws {
        var sockets = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer {
            if sockets[0] >= 0 { close(sockets[0]) }
            if sockets[1] >= 0 { close(sockets[1]) }
        }

        let flags = fcntl(sockets[0], F_GETFL)
        XCTAssertEqual(fcntl(sockets[0], F_SETFL, flags | O_NONBLOCK), 0)

        let queue = DispatchQueue(label: "NewlineDelimitedSocketReaderTests")
        var frames: [String] = []
        let eofDelivered = expectation(description: "EOF delivered")

        let reader = NewlineDelimitedSocketReader(
            fd: sockets[0],
            queue: queue,
            logger: Logger(label: "NewlineDelimitedSocketReaderTests"),
            delimiter: UInt8(ascii: ";"),
            onFrame: { frame in
                frames.append(String(decoding: frame, as: UTF8.self))
            },
            onEOF: { hasResidualData in
                XCTAssertFalse(hasResidualData)
                eofDelivered.fulfill()
            },
            onError: { XCTFail("Unexpected error: \($0)") }
        )

        try reader.start()

        let payload = Data("part1;part2;".utf8)
        let written = payload.withUnsafeBytes { bytes in
            write(sockets[1], bytes.baseAddress, bytes.count)
        }
        XCTAssertEqual(written, payload.count)

        XCTAssertEqual(shutdown(sockets[1], SHUT_WR), 0)
        wait(for: [eofDelivered], timeout: 1)

        XCTAssertEqual(frames, ["part1", "part2"])
    }

    func testEOFWithResidualData() throws {
        var sockets = [Int32](repeating: -1, count: 2)
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        defer {
            if sockets[0] >= 0 { close(sockets[0]) }
            if sockets[1] >= 0 { close(sockets[1]) }
        }

        let flags = fcntl(sockets[0], F_GETFL)
        XCTAssertEqual(fcntl(sockets[0], F_SETFL, flags | O_NONBLOCK), 0)

        let queue = DispatchQueue(label: "NewlineDelimitedSocketReaderTests")
        var frames: [String] = []
        let eofDelivered = expectation(description: "EOF delivered")

        let reader = NewlineDelimitedSocketReader(
            fd: sockets[0],
            queue: queue,
            logger: Logger(label: "NewlineDelimitedSocketReaderTests"),
            onFrame: { frame in
                frames.append(String(decoding: frame, as: UTF8.self))
            },
            onEOF: { hasResidualData in
                XCTAssertTrue(hasResidualData)
                eofDelivered.fulfill()
            },
            onError: { XCTFail("Unexpected error: \($0)") }
        )

        try reader.start()

        let payload = Data("complete\nresidual".utf8)
        let written = payload.withUnsafeBytes { bytes in
            write(sockets[1], bytes.baseAddress, bytes.count)
        }
        XCTAssertEqual(written, payload.count)

        XCTAssertEqual(shutdown(sockets[1], SHUT_WR), 0)
        wait(for: [eofDelivered], timeout: 1)

        XCTAssertEqual(frames, ["complete"])
    }

    func testStopBeforeStartDoesNotCrash() {
        let queue = DispatchQueue(label: "NewlineDelimitedSocketReaderTests")
        let reader = NewlineDelimitedSocketReader(
            fd: -1,
            queue: queue,
            logger: Logger(label: "NewlineDelimitedSocketReaderTests"),
            onFrame: { _ in },
            onEOF: { _ in },
            onError: { _ in }
        )

        reader.stop()

        // Ensure starting after stop does nothing and does not crash
        XCTAssertNoThrow(try reader.start())
    }
}
