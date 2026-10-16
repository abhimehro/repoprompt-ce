import Foundation
@testable import RepoPromptApp
import XCTest

final class ProviderErrorSanitizationTests: XCTestCase {
    func testErrorAsFriendlyStringSanitizesNSError() {
        let nsError = NSError(
            domain: "com.openai.error",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Invalid API Key provided"]
        )
        let friendly = (nsError as Error).asFriendlyString()
        XCTAssertTrue(friendly.contains("Unknown error") || friendly.contains("401"))
    }
}
