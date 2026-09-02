import Foundation

enum WorkspaceFileWrite {
    /// Publishes a complete new file without replacing a destination that appeared concurrently.
    static func atomicallyWithoutOverwriting(_ data: Data, to destinationURL: URL) throws {
        let temporaryURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
    }
}

enum WorkspaceSessionSidecarPreparedDestinationState {
    case absent
    case replace(expectedData: Data)
    case verifyOnly(expectedData: Data)

    var requiresWrite: Bool {
        switch self {
        case .absent, .replace:
            true
        case .verifyOnly:
            false
        }
    }
}

struct WorkspaceSessionSidecarPreparedCopy {
    let sourceURL: URL
    let expectedSourceData: Data
    let destinationURL: URL
    let data: Data
    let modificationDate: Date?
    let destinationState: WorkspaceSessionSidecarPreparedDestinationState
}

struct WorkspaceSessionSidecarPreparedBatch {
    let sourceFolder: URL
    let destinationFolder: URL
    let filenamePrefix: String
    let copies: [WorkspaceSessionSidecarPreparedCopy]
}

enum WorkspaceSessionSidecarMigrationError: LocalizedError {
    case invalidSessionFile(URL)
    case sessionIdentityMismatch(URL)
    case divergentCollision(URL)
    case ambiguousWorkspaceDirectories(workspaceID: UUID, candidates: [URL])
    case workspaceDirectoryScanFailed(workspaceID: UUID, root: URL, reason: String)
    case aliasedSessionFolders(source: URL, destination: URL)
    case sourceChanged(URL)
    case destinationChanged(URL)
    case sourceWriteInProgress(URL)
    case destinationWriteInProgress(URL)

    var errorDescription: String? {
        switch self {
        case let .invalidSessionFile(url):
            "Invalid session sidecar: \(url.lastPathComponent)"
        case let .sessionIdentityMismatch(url):
            "Session identity does not match its filename: \(url.lastPathComponent)"
        case let .divergentCollision(url):
            "A different session already exists in the canonical workspace: \(url.lastPathComponent)"
        case let .ambiguousWorkspaceDirectories(workspaceID, candidates):
            "Multiple session directories match \(workspaceID.uuidString): "
                + candidates.map(\.path).joined(separator: ", ")
        case let .workspaceDirectoryScanFailed(workspaceID, root, reason):
            "Unable to resolve session storage for \(workspaceID.uuidString) under \(root.path): \(reason)"
        case let .aliasedSessionFolders(source, destination):
            "Source and destination session folders resolve to the same directory: "
                + "\(source.path), \(destination.path)"
        case let .sourceChanged(url):
            "The source sessions changed after preflight: \(url.lastPathComponent)"
        case let .destinationChanged(url):
            "The destination session changed after preflight: \(url.lastPathComponent)"
        case let .sourceWriteInProgress(url):
            "The source session has a pending write: \(url.lastPathComponent)"
        case let .destinationWriteInProgress(url):
            "The destination session has a pending write: \(url.lastPathComponent)"
        }
    }
}

enum WorkspaceSessionSidecarMigration {
    /// Resolves a model to its historical sidecar directory without requiring a workspace document.
    /// Custom per-workspace storage remains authoritative. Otherwise every immediate directory
    /// carrying the UUID suffix is considered, so a rename can reuse a sidecar-only directory.
    static func workspaceDirectory(
        for workspace: WorkspaceModel,
        root: URL,
        requireUniqueMatch: Bool = false
    ) throws -> URL {
        if let customStoragePath = workspace.customStoragePath {
            return customStoragePath.standardizedFileURL
        }

        let standardizedRoot = root.standardizedFileURL
        let derived = standardizedRoot.appendingPathComponent(
            WorkspaceDirectoryName.directoryName(name: workspace.name, id: workspace.id),
            isDirectory: true
        )
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedRoot.path, isDirectory: &isDirectory) else {
            return derived
        }
        guard isDirectory.boolValue else {
            throw WorkspaceSessionSidecarMigrationError.workspaceDirectoryScanFailed(
                workspaceID: workspace.id,
                root: standardizedRoot,
                reason: "The session storage root is not a directory."
            )
        }

        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: standardizedRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw WorkspaceSessionSidecarMigrationError.workspaceDirectoryScanFailed(
                workspaceID: workspace.id,
                root: standardizedRoot,
                reason: error.localizedDescription
            )
        }

        var matches: [URL] = []
        for child in children {
            guard WorkspaceDirectoryName.parse(child.lastPathComponent).id == workspace.id else {
                continue
            }
            do {
                guard try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                    continue
                }
            } catch {
                throw WorkspaceSessionSidecarMigrationError.workspaceDirectoryScanFailed(
                    workspaceID: workspace.id,
                    root: standardizedRoot,
                    reason: error.localizedDescription
                )
            }
            matches.append(child.standardizedFileURL)
        }

        if matches.count > 1 {
            guard requireUniqueMatch else {
                // Preserve the predecessor's ordinary read/write locus for historical layouts
                // split across multiple name-derived directories. Consolidation opts into strict
                // uniqueness so it can never retire a workspace after copying only one fragment.
                return derived
            }
            throw WorkspaceSessionSidecarMigrationError.ambiguousWorkspaceDirectories(
                workspaceID: workspace.id,
                candidates: matches.sorted { $0.path < $1.path }
            )
        }
        return matches.first ?? derived
    }

    static func validateDistinctSessionFolders(
        source sourceFolder: URL,
        destination destinationFolder: URL
    ) throws {
        let physicalSource = sourceFolder.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let physicalDestination = destinationFolder.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard physicalSource != physicalDestination else {
            throw WorkspaceSessionSidecarMigrationError.aliasedSessionFolders(
                source: sourceFolder,
                destination: destinationFolder
            )
        }
    }

    static func sessionFileURLs(in folder: URL, prefix: String) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.lastPathComponent.hasPrefix(prefix),
                  url.pathExtension.lowercased() == "json"
            else { return false }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func prepareCopies(
        from sourceFolder: URL,
        to destinationFolder: URL,
        filenamePrefix: String,
        canonicalWorkspaceID: UUID
    ) throws -> [WorkspaceSessionSidecarPreparedCopy] {
        let sourceFiles = try sessionFileURLs(in: sourceFolder, prefix: filenamePrefix)
        guard !sourceFiles.isEmpty else { return [] }

        var prepared: [WorkspaceSessionSidecarPreparedCopy] = []
        prepared.reserveCapacity(sourceFiles.count)
        for sourceURL in sourceFiles {
            let sessionID = try sessionID(
                from: sourceURL,
                filenamePrefix: filenamePrefix
            )
            let destinationURL = destinationFolder
                .appendingPathComponent(sourceURL.lastPathComponent)
                .standardizedFileURL
            let sourceData = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
            let normalizedSource = try normalizedPayload(
                sourceData,
                expectedSessionID: sessionID,
                canonicalWorkspaceID: canonicalWorkspaceID,
                destinationURL: destinationURL
            )

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                let destinationData = try Data(contentsOf: destinationURL, options: .mappedIfSafe)
                let normalizedDestination = try normalizedPayload(
                    destinationData,
                    expectedSessionID: sessionID,
                    canonicalWorkspaceID: canonicalWorkspaceID,
                    destinationURL: destinationURL
                )
                guard normalizedDestination.data == normalizedSource.data else {
                    throw WorkspaceSessionSidecarMigrationError.divergentCollision(destinationURL)
                }

                let destinationState: WorkspaceSessionSidecarPreparedDestinationState
                let modificationDate: Date?
                if normalizedDestination.alreadyRehomed {
                    destinationState = .verifyOnly(expectedData: destinationData)
                    modificationDate = nil
                } else {
                    destinationState = .replace(expectedData: destinationData)
                    modificationDate = try? destinationURL.resourceValues(
                        forKeys: [.contentModificationDateKey]
                    ).contentModificationDate
                }
                prepared.append(WorkspaceSessionSidecarPreparedCopy(
                    sourceURL: sourceURL,
                    expectedSourceData: sourceData,
                    destinationURL: destinationURL,
                    data: normalizedDestination.data,
                    modificationDate: modificationDate,
                    destinationState: destinationState
                ))
            } else {
                let modificationDate = try? sourceURL.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                prepared.append(WorkspaceSessionSidecarPreparedCopy(
                    sourceURL: sourceURL,
                    expectedSourceData: sourceData,
                    destinationURL: destinationURL,
                    data: normalizedSource.data,
                    modificationDate: modificationDate,
                    destinationState: .absent
                ))
            }
        }
        return prepared
    }

    static func validatePreparedSources(_ batch: WorkspaceSessionSidecarPreparedBatch) throws {
        let currentSourceURLs = try sessionFileURLs(
            in: batch.sourceFolder,
            prefix: batch.filenamePrefix
        ).map(\.standardizedFileURL)
        let expectedSourceURLs = batch.copies.map(\.sourceURL.standardizedFileURL)
        guard Set(currentSourceURLs) == Set(expectedSourceURLs) else {
            throw WorkspaceSessionSidecarMigrationError.sourceChanged(batch.sourceFolder)
        }
        for copy in batch.copies {
            guard let currentData = try? Data(
                contentsOf: copy.sourceURL,
                options: .mappedIfSafe
            ), currentData == copy.expectedSourceData
            else {
                throw WorkspaceSessionSidecarMigrationError.sourceChanged(copy.sourceURL)
            }
        }
    }

    /// Performs the commit's complete destination validation before any filesystem mutation.
    static func validatePreparedCopies(_ copies: [WorkspaceSessionSidecarPreparedCopy]) throws {
        let fileManager = FileManager.default
        for copy in copies {
            switch copy.destinationState {
            case .absent:
                guard !fileManager.fileExists(atPath: copy.destinationURL.path) else {
                    throw WorkspaceSessionSidecarMigrationError.destinationChanged(copy.destinationURL)
                }
            case let .replace(expectedData), let .verifyOnly(expectedData):
                guard let currentData = try? Data(
                    contentsOf: copy.destinationURL,
                    options: .mappedIfSafe
                ), currentData == expectedData
                else {
                    throw WorkspaceSessionSidecarMigrationError.destinationChanged(copy.destinationURL)
                }
            }
        }
    }

    /// Commits a prepared batch synchronously. Callers must invoke this inside their service's
    /// serialization boundary so validation cannot be interleaved with an in-process normal save.
    static func commitPreparedBatch(_ batch: WorkspaceSessionSidecarPreparedBatch) throws {
        try validateDistinctSessionFolders(
            source: batch.sourceFolder,
            destination: batch.destinationFolder
        )
        try validatePreparedSources(batch)
        try validatePreparedCopies(batch.copies)
        guard batch.copies.contains(where: \.destinationState.requiresWrite) else {
            return
        }

        try FileManager.default.createDirectory(
            at: batch.destinationFolder,
            withIntermediateDirectories: true
        )
        for copy in batch.copies {
            switch copy.destinationState {
            case .absent:
                try WorkspaceFileWrite.atomicallyWithoutOverwriting(
                    copy.data,
                    to: copy.destinationURL
                )
            case .replace:
                try copy.data.write(to: copy.destinationURL, options: .atomic)
            case .verifyOnly:
                continue
            }
            if let modificationDate = copy.modificationDate {
                try FileManager.default.setAttributes(
                    [.modificationDate: modificationDate],
                    ofItemAtPath: copy.destinationURL.path
                )
            }
        }
    }

    private struct NormalizedPayload {
        let data: Data
        let alreadyRehomed: Bool
    }

    private static func normalizedPayload(
        _ data: Data,
        expectedSessionID: UUID,
        canonicalWorkspaceID: UUID,
        destinationURL: URL
    ) throws -> NormalizedPayload {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawSessionID = object["id"] as? String,
              let embeddedSessionID = UUID(uuidString: rawSessionID)
        else {
            throw WorkspaceSessionSidecarMigrationError.invalidSessionFile(destinationURL)
        }
        guard embeddedSessionID == expectedSessionID else {
            throw WorkspaceSessionSidecarMigrationError.sessionIdentityMismatch(destinationURL)
        }

        let canonicalWorkspaceIDString = canonicalWorkspaceID.uuidString
        let destinationURLString = destinationURL.absoluteString
        let alreadyRehomed = (object["workspaceID"] as? String) == canonicalWorkspaceIDString
            && (object["fileURL"] as? String) == destinationURLString
        object["workspaceID"] = canonicalWorkspaceIDString
        object["fileURL"] = destinationURLString
        let normalizedData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        return NormalizedPayload(
            data: normalizedData,
            alreadyRehomed: alreadyRehomed
        )
    }

    private static func sessionID(
        from fileURL: URL,
        filenamePrefix: String
    ) throws -> UUID {
        let filename = fileURL.deletingPathExtension().lastPathComponent
        guard filename.hasPrefix(filenamePrefix) else {
            throw WorkspaceSessionSidecarMigrationError.invalidSessionFile(fileURL)
        }
        let rawID = String(filename.dropFirst(filenamePrefix.count))
        guard let id = UUID(uuidString: rawID) else {
            throw WorkspaceSessionSidecarMigrationError.invalidSessionFile(fileURL)
        }
        return id
    }
}
