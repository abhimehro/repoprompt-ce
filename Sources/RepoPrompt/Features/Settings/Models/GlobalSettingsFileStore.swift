import Foundation

protocol GlobalSettingsFileStoring {
    var fileURL: URL { get }

    func load() throws -> GlobalSettingsDocument
    func loadOrCreateDefault() -> GlobalSettingsDocument
    func save(_ document: GlobalSettingsDocument) throws
}

/// File-backed store for the versioned global settings document.
///
/// Primary location:
/// `~/Library/Application Support/RepoPrompt CE/Settings/globalSettings.json`
final class GlobalSettingsFileStore: GlobalSettingsFileStoring {
    static let appSupportDirectoryName = "RepoPrompt CE"
    static let settingsDirectoryName = "Settings"
    static let filename = "globalSettings.json"

    let fileURL: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private var preservingUnsupportedFutureDocument = false
    private var preservingUnbackedCorruptDocument = false

    init(
        fileURL: URL = GlobalSettingsFileStore.defaultFileURL(),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.now = now
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        settingsDirectoryURL(fileManager: fileManager)
            .appendingPathComponent(filename)
    }

    static func settingsDirectoryURL(fileManager: FileManager = .default) -> URL {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return supportDirectory
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(settingsDirectoryName, isDirectory: true)
    }

    func load() throws -> GlobalSettingsDocument {
        let data = try Data(contentsOf: fileURL)
        let header = try Self.decoder.decode(GlobalSettingsDocumentHeader.self, from: data)
        guard header.schemaVersion <= GlobalSettingsDocument.currentSchemaVersion else {
            preservingUnsupportedFutureDocument = true
            throw GlobalSettingsFileStoreError.unsupportedFutureSchema(header.schemaVersion)
        }
        preservingUnsupportedFutureDocument = false
        preservingUnbackedCorruptDocument = false
        return try Self.decoder.decode(GlobalSettingsDocument.self, from: data)
    }

    func loadOrCreateDefault() -> GlobalSettingsDocument {
        preservingUnsupportedFutureDocument = false
        preservingUnbackedCorruptDocument = false
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                var document = try load()
                if document.schemaVersion < GlobalSettingsDocument.currentSchemaVersion {
                    document.schemaVersion = GlobalSettingsDocument.currentSchemaVersion
                    writeFallbackDocument(document)
                }
                return document
            } catch let GlobalSettingsFileStoreError.unsupportedFutureSchema(version) {
                preservingUnsupportedFutureDocument = true
                print("⚠️ Global settings JSON schema v\(version) is newer than supported v\(GlobalSettingsDocument.currentSchemaVersion); preserving file and using in-memory defaults for this launch.")
                return defaultDocument()
            } catch {
                let fallback = defaultDocument()
                if backupCorruptFile(error: error) {
                    writeFallbackDocument(fallback)
                } else {
                    preservingUnbackedCorruptDocument = true
                }
                return fallback
            }
        }

        let document = defaultDocument()
        writeFallbackDocument(document)
        return document
    }

    func save(_ document: GlobalSettingsDocument) throws {
        guard !preservingUnsupportedFutureDocument else {
            throw GlobalSettingsFileStoreError.unsupportedFutureSchemaPreserved
        }
        guard !preservingUnbackedCorruptDocument else {
            throw GlobalSettingsFileStoreError.corruptDocumentPreserved
        }
        if let futureVersion = unsupportedFutureSchemaVersionOnDisk() {
            preservingUnsupportedFutureDocument = true
            print("⚠️ Global settings JSON schema v\(futureVersion) is newer than supported v\(GlobalSettingsDocument.currentSchemaVersion); preserving file and skipping save.")
            throw GlobalSettingsFileStoreError.unsupportedFutureSchemaPreserved
        }
        try ensureSettingsDirectoryExists()
        var documentToWrite = document
        documentToWrite.schemaVersion = max(document.schemaVersion, GlobalSettingsDocument.currentSchemaVersion)
        documentToWrite.updatedAt = now()
        let data = try Self.encoder.encode(documentToWrite)
        try data.write(to: fileURL, options: .atomic)
    }

    private func defaultDocument() -> GlobalSettingsDocument {
        GlobalSettingsDocument(
            updatedAt: now(),
            globalDefaults: GlobalDefaults(discoverAgentRaw: nil, discoverModelsByAgent: nil),
            scalarPreferences: GlobalScalarPreferences()
        )
    }

    private func writeFallbackDocument(_ document: GlobalSettingsDocument) {
        do {
            try save(document)
        } catch {
            print("⚠️ Failed to write global settings JSON at \(fileURL.path): \(error)")
        }
    }

    private func ensureSettingsDirectoryExists() throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func backupCorruptFile(error: Error) -> Bool {
        do {
            let backupDirectory = fileURL
                .deletingLastPathComponent()
                .appendingPathComponent("Backups", isDirectory: true)
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

            var backupURL = backupDirectory
                .appendingPathComponent("globalSettings.corrupt-\(Self.backupTimestamp(for: now())).json")
            if fileManager.fileExists(atPath: backupURL.path) {
                backupURL = backupDirectory
                    .appendingPathComponent("globalSettings.corrupt-\(Self.backupTimestamp(for: now()))-\(UUID().uuidString).json")
            }

            do {
                try fileManager.moveItem(at: fileURL, to: backupURL)
            } catch {
                try fileManager.copyItem(at: fileURL, to: backupURL)
                try? fileManager.removeItem(at: fileURL)
            }
            print("⚠️ Backed up corrupt global settings JSON to \(backupURL.path): \(error)")
            return true
        } catch {
            print("⚠️ Failed to back up corrupt global settings JSON at \(fileURL.path): \(error)")
            return false
        }
    }

    private func unsupportedFutureSchemaVersionOnDisk() -> Int? {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let header = try? Self.decoder.decode(GlobalSettingsDocumentHeader.self, from: data),
              header.schemaVersion > GlobalSettingsDocument.currentSchemaVersion
        else {
            return nil
        }
        return header.schemaVersion
    }

    private static let backupTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func backupTimestamp(for date: Date) -> String {
        return backupTimestampFormatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }

    private struct GlobalSettingsDocumentHeader: Decodable {
        let schemaVersion: Int
    }

    enum GlobalSettingsFileStoreError: Error, Equatable {
        case unsupportedFutureSchema(Int)
        case unsupportedFutureSchemaPreserved
        case corruptDocumentPreserved
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
