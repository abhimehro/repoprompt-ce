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

/// Resolves one workspace UUID to one physical directory without deriving identity from a mutable
/// display name. The memo is process-wide because the manager, Agent sessions, and Chats all write
/// the same storage tree from different isolation domains.
final class WorkspaceStorageDirectoryResolver: @unchecked Sendable {
    static let shared = WorkspaceStorageDirectoryResolver()

    private enum Provenance {
        case custom(path: String)
        case catalog
        case discovered(rootPath: String)
    }

    private struct MemoEntry {
        let directory: URL
        let provenance: Provenance
    }

    private let lock = NSLock()
    private var memoByWorkspaceID: [UUID: MemoEntry] = [:]
    private let maximumRootEntryCount = 1024

    func resolveDirectory(
        workspaceID: UUID,
        workspaceName: String,
        customStoragePath: URL?,
        catalogFileURL: URL?,
        baseRoot: URL
    ) throws -> URL {
        if let customStoragePath {
            let directory = customStoragePath.standardizedFileURL
            store(
                MemoEntry(directory: directory, provenance: .custom(path: directory.path)),
                workspaceID: workspaceID
            )
            return directory
        }

        if let catalogFileURL {
            let directory = catalogFileURL.deletingLastPathComponent().standardizedFileURL
            store(MemoEntry(directory: directory, provenance: .catalog), workspaceID: workspaceID)
            return directory
        }

        let standardizedRoot = baseRoot.standardizedFileURL
        if let memoized = compatibleMemo(workspaceID: workspaceID, baseRoot: standardizedRoot) {
            return memoized
        }

        let derived = standardizedRoot.appendingPathComponent(
            DomainWorkspaceStoragePath.directoryName(name: workspaceName, id: workspaceID),
            isDirectory: true
        )
        if try containsWorkspaceDocument(derived, workspaceID: workspaceID, root: standardizedRoot) {
            store(
                MemoEntry(
                    directory: derived.standardizedFileURL,
                    provenance: .discovered(rootPath: standardizedRoot.path)
                ),
                workspaceID: workspaceID
            )
            return derived.standardizedFileURL
        }

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
        guard children.count <= maximumRootEntryCount else {
            throw WorkspaceStorageDirectoryResolutionError.scanFailed(
                workspaceID: workspaceID,
                root: standardizedRoot,
                reason: "The root contains more than \(maximumRootEntryCount) entries."
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
            store(
                MemoEntry(
                    directory: match,
                    provenance: .discovered(rootPath: standardizedRoot.path)
                ),
                workspaceID: workspaceID
            )
            return match
        }

        // A complete scan found no persisted incarnation. Returning the sanitized derived path is
        // therefore a creation target, not a guess made under filesystem uncertainty.
        return derived
    }

    func noteCatalogFileURLs(_ fileURLsByWorkspaceID: [UUID: URL]) {
        lock.lock()
        let projectedIDs = Set(fileURLsByWorkspaceID.keys)
        let retiredCatalogIDs = memoByWorkspaceID.compactMap { workspaceID, entry -> UUID? in
            guard case .catalog = entry.provenance,
                  !projectedIDs.contains(workspaceID)
            else { return nil }
            return workspaceID
        }
        for workspaceID in retiredCatalogIDs {
            memoByWorkspaceID.removeValue(forKey: workspaceID)
        }
        for (workspaceID, fileURL) in fileURLsByWorkspaceID {
            memoByWorkspaceID[workspaceID] = MemoEntry(
                directory: fileURL.deletingLastPathComponent().standardizedFileURL,
                provenance: .catalog
            )
        }
        lock.unlock()
    }

    func evict(workspaceID: UUID) {
        lock.lock()
        memoByWorkspaceID.removeValue(forKey: workspaceID)
        lock.unlock()
    }

    #if DEBUG
        func removeAllForTesting() {
            lock.lock()
            memoByWorkspaceID.removeAll()
            lock.unlock()
        }
    #endif

    private func compatibleMemo(workspaceID: UUID, baseRoot: URL) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = memoByWorkspaceID[workspaceID] else { return nil }
        switch entry.provenance {
        case .catalog:
            return entry.directory
        case let .discovered(rootPath):
            return rootPath == baseRoot.path ? entry.directory : nil
        case .custom:
            // The current model no longer supplies a custom path, so a prior custom memo must not
            // outlive that explicit setting.
            return nil
        }
    }

    private func store(_ entry: MemoEntry, workspaceID: UUID) {
        lock.lock()
        memoByWorkspaceID[workspaceID] = entry
        lock.unlock()
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
