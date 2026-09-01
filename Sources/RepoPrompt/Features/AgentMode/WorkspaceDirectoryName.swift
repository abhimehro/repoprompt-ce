import Foundation
import RepoPromptDomainRuntime

/// On-disk workspace directory naming convention: `Workspace-{name}-{uuid}`.
///
/// The format is parsed by `HistorySessionScanner` for cross-workspace discovery. Live storage
/// resolution is UUID/catalog based; this builder delegates to the domain sanitizer for legacy
/// callers that still need a creation name.
enum WorkspaceDirectoryName {
    static let prefix = "Workspace-"

    /// Build a directory name from a workspace name and UUID.
    static func directoryName(name: String, id: UUID) -> String {
        DomainWorkspaceStoragePath.directoryName(name: name, id: id)
    }

    /// Parse `Workspace-{name}-{uuid}` into `(name, id)`. Workspace names may contain
    /// hyphens, so the UUID is matched as the trailing hyphen-delimited segment that
    /// parses. Falls back to the raw directory name (with no id) when parsing fails.
    static func parse(_ dirName: String) -> (name: String, id: UUID?) {
        guard dirName.hasPrefix(prefix) else {
            return (name: dirName, id: nil)
        }

        let withoutPrefix = String(dirName.dropFirst(prefix.count))

        // The UUID is the last hyphen-delimited segment that parses as a UUID.
        // Workspace names may contain hyphens, so scan from the end.
        let components = withoutPrefix.components(separatedBy: "-")
        for i in stride(from: components.count - 1, through: 1, by: -1) {
            // UUID format: 8-4-4-4-12 = 5 components joined by hyphens
            let potentialUUID = components[i...].joined(separator: "-")
            if let uuid = UUID(uuidString: potentialUUID) {
                let namePart = components[..<i].joined(separator: "-")
                return (name: namePart.isEmpty ? dirName : namePart, id: uuid)
            }
        }

        return (name: withoutPrefix, id: nil)
    }
}
