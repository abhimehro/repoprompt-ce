import Foundation
import RepoPromptDomainRuntime

enum WorkspaceStorageDirectoryResolutionError: LocalizedError {
    case ambiguousDirectories(workspaceID: UUID, candidates: [URL])
    case scanFailed(workspaceID: UUID, root: URL, reason: String)

    var errorDescription: String? {
        switch self {
        case let .ambiguousDirectories(workspaceID, candidates):
            let paths = candidates.map(\.path).joined(separator: ", ")
            return "Multiple workspace directories match \(workspaceID.uuidString): \(paths)"
        case let .scanFailed(workspaceID, root, reason):
            return "Unable to resolve workspace \(workspaceID.uuidString) under \(root.path): \(reason)"
        }
    }
}

/// Resolves one workspace UUID to one physical document directory without deriving identity from a
/// mutable display name. Resolution is deliberately stateless: callers with an authoritative
/// catalog URL supply it on each call, while legacy callers scan only the root they provide.
final class WorkspaceStorageDirectoryResolver: Sendable {
    static let shared = WorkspaceStorageDirectoryResolver()

    func resolveDirectory(
        workspaceID: UUID,
        workspaceName: String,
        customStoragePath: URL?,
        catalogFileURL: URL?,
        baseRoot: URL
    ) throws -> URL {
        if let customStoragePath {
            return customStoragePath.standardizedFileURL
        }

        if let catalogFileURL {
            return catalogFileURL.deletingLastPathComponent().standardizedFileURL
        }

        let standardizedRoot = baseRoot.standardizedFileURL
        let derived = standardizedRoot.appendingPathComponent(
            DomainWorkspaceStoragePath.directoryName(name: workspaceName, id: workspaceID),
            isDirectory: true
        )
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedRoot.path, isDirectory: &isDirectory) else {
            return derived
        }
        guard isDirectory.boolValue else {
            throw WorkspaceStorageDirectoryResolutionError.scanFailed(
                workspaceID: workspaceID,
                root: standardizedRoot,
                reason: "The workspace storage root is not a directory."
            )
        }

        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: standardizedRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw WorkspaceStorageDirectoryResolutionError.scanFailed(
                workspaceID: workspaceID,
                root: standardizedRoot,
                reason: error.localizedDescription
            )
        }
        var matches: [URL] = []
        for child in children {
            guard WorkspaceDirectoryName.parse(child.lastPathComponent).id == workspaceID else { continue }
            do {
                guard try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
            } catch {
                throw WorkspaceStorageDirectoryResolutionError.scanFailed(
                    workspaceID: workspaceID,
                    root: standardizedRoot,
                    reason: error.localizedDescription
                )
            }
            if try containsWorkspaceDocument(child, workspaceID: workspaceID, root: standardizedRoot) {
                matches.append(child.standardizedFileURL)
            }
        }

        guard matches.count <= 1 else {
            throw WorkspaceStorageDirectoryResolutionError.ambiguousDirectories(
                workspaceID: workspaceID,
                candidates: matches.sorted { $0.path < $1.path }
            )
        }
        if let match = matches.first {
            return match
        }

        // A complete scan found no persisted incarnation. Returning the sanitized derived path is
        // therefore a creation target, not a guess made under filesystem uncertainty.
        return derived
    }

    private func containsWorkspaceDocument(
        _ directory: URL,
        workspaceID: UUID,
        root: URL
    ) throws -> Bool {
        let document = directory.appendingPathComponent("workspace.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: document.path) else { return false }
        do {
            return try document.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        } catch {
            throw WorkspaceStorageDirectoryResolutionError.scanFailed(
                workspaceID: workspaceID,
                root: root,
                reason: error.localizedDescription
            )
        }
    }
}
