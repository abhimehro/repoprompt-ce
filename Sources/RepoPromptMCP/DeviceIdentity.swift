import Foundation

struct DeviceIdentity {
    static let shared = DeviceIdentity()
    let id: String

    private init() {
        let fm = FileManager.default
        let baseDir = fm.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("com.repoprompt", isDirectory: true)
        let fileURL = baseDir.appendingPathComponent("device-id")

        #if DEBUG
            fputs("CLI DeviceIdentity: Looking for device ID at: \(fileURL.path)\n", stderr)
        #endif

        try? fm.createDirectory(
            at: baseDir,
            withIntermediateDirectories: true
        )

        if let data = try? Data(contentsOf: fileURL),
           let str = String(data: data, encoding: .utf8)?
           .trimmingCharacters(in: .whitespacesAndNewlines),
           !str.isEmpty
        {
            id = str
            #if DEBUG
                fputs("CLI DeviceIdentity: Loaded existing device ID: \(str)\n", stderr)
            #endif
        } else {
            let newID = UUID().uuidString
            if let data = newID.data(using: .utf8) {
                // SECURITY: Prevent TOCTOU race condition by creating file with secure permissions first
                let tempURL = fileURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
                if FileManager.default.createFile(atPath: tempURL.path, contents: data, attributes: [.posixPermissions: 0o600]) {
                    do {
                        if fm.fileExists(atPath: fileURL.path) {
                            #if os(macOS)
                            _ = try fm.replaceItem(at: fileURL, withItemAt: tempURL, backupItemName: nil, options: [.usingNewMetadataOnly])
                            #else
                            try? FileManager.default.removeItem(at: fileURL)
                            try FileManager.default.moveItem(at: tempURL, to: fileURL)
                            #endif
                        } else {
                            try FileManager.default.moveItem(at: tempURL, to: fileURL)
                        }
                    } catch {
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                }
            }
            id = newID
            #if DEBUG
                fputs("CLI DeviceIdentity: Created new device ID: \(newID)\n", stderr)
            #endif
        }
    }
}
