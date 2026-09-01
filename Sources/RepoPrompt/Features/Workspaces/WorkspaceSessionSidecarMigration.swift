import Foundation

struct WorkspaceSessionSidecarPreparedCopy {
    let destinationURL: URL
    let data: Data
    let modificationDate: Date?
}

struct WorkspaceSessionSidecarPreparedBatch {
    let destinationFolder: URL
    let copies: [WorkspaceSessionSidecarPreparedCopy]
}

enum WorkspaceSessionSidecarMigrationError: LocalizedError {
    case invalidSessionFile(URL)
    case sessionIdentityMismatch(URL)
    case divergentCollision(URL)

    var errorDescription: String? {
        switch self {
        case let .invalidSessionFile(url):
            "Invalid session sidecar: \(url.lastPathComponent)"
        case let .sessionIdentityMismatch(url):
            "Session identity does not match its filename: \(url.lastPathComponent)"
        case let .divergentCollision(url):
            "A different session already exists in the canonical workspace: \(url.lastPathComponent)"
        }
    }
}

enum WorkspaceSessionSidecarMigration {
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
            let destinationURL = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
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
                guard !normalizedDestination.alreadyRehomed else { continue }
                let modificationDate = try? destinationURL.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                prepared.append(WorkspaceSessionSidecarPreparedCopy(
                    destinationURL: destinationURL,
                    data: normalizedDestination.data,
                    modificationDate: modificationDate
                ))
            } else {
                let modificationDate = try? sourceURL.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                prepared.append(WorkspaceSessionSidecarPreparedCopy(
                    destinationURL: destinationURL,
                    data: normalizedSource.data,
                    modificationDate: modificationDate
                ))
            }
        }
        return prepared
    }

    static func write(_ prepared: WorkspaceSessionSidecarPreparedCopy) throws {
        try prepared.data.write(to: prepared.destinationURL, options: .atomic)
        if let modificationDate = prepared.modificationDate {
            try FileManager.default.setAttributes(
                [.modificationDate: modificationDate],
                ofItemAtPath: prepared.destinationURL.path
            )
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
