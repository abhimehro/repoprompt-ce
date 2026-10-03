import Foundation

/// Determines how CodeMap definitions are inserted.
enum CodeMapUsage: String, CaseIterable, Codable {
    case auto
    case complete
    /// Include code-map for selected files only (handled at injection sites;
    /// returning it here would duplicate).
    case selected
    case none
}

/// File tree build result with marker flags
struct FileTreeResult {
    let tree: String
    let usedSelectedMarker: Bool
    let usedCodeMapMarker: Bool
    let wasTruncated: Bool
    let note: String?
    var usesLegend: Bool {
        usedSelectedMarker || usedCodeMapMarker
    }
}

/// Namespace for immutable file-tree presentation.
enum CodeMapExtractor {}
