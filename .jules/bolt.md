## YYYY-MM-DD - DateFormatter initialization overhead
**Learning:** In Swift, DateFormatter and ISO8601DateFormatter are extremely expensive to initialize. I found hundreds of inline instantiations in Changelog.swift, which is a significant performance bottleneck.
**Action:** Extract inline DateFormatter/ISO8601DateFormatter initializations to a static singleton (e.g., `nonisolated(unsafe) static let dateFormatter = ISO8601DateFormatter()`) and reuse it across the type.
