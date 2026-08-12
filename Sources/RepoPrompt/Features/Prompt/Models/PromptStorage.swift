//
//  PromptStorage.swift
//  RepoPrompt
//
//  Created by Eric Provencher on 2025-03-21.
//

import Foundation

/// <summary>
/// Represents the external structure used for importing and exporting prompts,
/// without relying on our internal UUID.
/// </summary>
struct PromptExport: Codable, Equatable {
    let title: String
    let content: String
}

/// <summary>
/// Manages reading and writing the user's saved prompts as JSON
/// in the app's Application Support/com.pvncher.repoprompt directory,
/// using a static dispatch queue for safe, atomic operations.
/// </summary>
class PromptStorage {
    static let shared = PromptStorage()

    private let filename = "SavedPrompts.json"

    /// This serial queue ensures file reads/writes are never interleaved.
    private static let queue = DispatchQueue(label: "com.pvncher.repoprompt.PromptStorageQueue")

    /// Compute the file URL in Application Support under com.pvncher.repoprompt
    private var fileURL: URL {
        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        // Create a subfolder "com.pvncher.repoprompt" if it doesn't exist
        let appSupportFolder = supportDir.appendingPathComponent("com.pvncher.repoprompt", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: appSupportFolder,
            withIntermediateDirectories: true
        )

        return appSupportFolder.appendingPathComponent(filename)
    }

    /// <summary>
    /// Reads the user's saved prompts from the JSON file.
    /// Returns a Result containing either the loaded prompts or an error.
    /// Returns .success([]) if the file doesn't exist (first run scenario).
    /// Returns .failure(error) if the file exists but can't be read/decoded.
    /// </summary>
    func loadPrompts() -> Result<[PromptViewModel.StoredPrompt], Error> {
        var result: Result<[PromptViewModel.StoredPrompt], Error> = .success([])

        // Use a synchronous block so we can return the result directly
        Self.queue.sync {
            // Check if the file exists first
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                // First run - no prompts file exists yet, return empty array
                result = .success([])
                return
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let prompts = try JSONDecoder().decode([PromptViewModel.StoredPrompt].self, from: data)
                result = .success(prompts)
            } catch {
                // File exists but can't be read or decoded - this is an error!
                print("⚠️ ERROR: Failed to load prompts from \(fileURL.path): \(error)")
                print("⚠️ This could indicate file corruption or permissions issues.")
                print("⚠️ User prompts will NOT be overwritten to prevent data loss.")
                result = .failure(error)
            }
        }

        return result
    }

    /// <summary>
    /// Writes (overwrites) the user's prompts to the JSON file atomically.
    /// This version supports an optional callback that fires after success/failure.
    /// </summary>
    func savePrompts(
        _ prompts: [PromptViewModel.StoredPrompt],
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        Self.queue.async {
            do {
                let data = try JSONEncoder().encode(prompts)
                // Use .atomicWrite so it writes to a temp file, then renames it on success
                try data.write(to: self.fileURL, options: .atomicWrite)

                // If we got here, the write succeeded.
                // Jump back to the main thread (or stay on the same queue) to call completion:
                DispatchQueue.main.async {
                    completion?(.success(()))
                }
            } catch {
                print("Failed to write prompts: \(error)")

                // If there's an error, pass it back via completion as well
                DispatchQueue.main.async {
                    completion?(.failure(error))
                }
            }
        }
    }
}

extension PromptStorage {
    /// <summary>
    /// Export our internal `StoredPrompt` array into an array of `PromptExport` for writing to disk.
    /// </summary>
    func exportPrompts(to url: URL, prompts: [PromptViewModel.StoredPrompt]) throws {
        let exports = prompts.map { PromptExport(title: $0.title, content: $0.content) }
        let data = try JSONEncoder().encode(exports)

        // Use atomic write
        try data.write(to: url, options: .atomicWrite)
    }

    /// <summary>
    /// Reads a JSON file from the specified URL and decodes it into an array of `PromptExport`.
    /// </summary>
    func loadExternalPrompts(from url: URL) throws -> [PromptExport] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([PromptExport].self, from: data)
    }

    /// <summary>
    /// Given the array of existing `StoredPrompt` and newly loaded external `PromptExport`,
    /// convert the external prompts into new `StoredPrompt`s, skipping duplicates.
    /// Returns a tuple: (merged array, count of new items).
    ///
    /// Duplicates are checked by matching (title, content).
    /// If a prompt with the same title + content already exists, we skip adding a new one.
    /// Otherwise, create a new `StoredPrompt` with a fresh UUID.
    /// </summary>
    func mergeExternalPrompts(
        current: [PromptViewModel.StoredPrompt],
        external: [PromptExport]
    ) -> (merged: [PromptViewModel.StoredPrompt], addedCount: Int) {
        var merged = current
        var addedCount = 0

        for item in external {
            // Check duplicates by (title, content)
            let duplicateExists = merged.contains(where: {
                $0.title == item.title && $0.content == item.content
            })

            if !duplicateExists {
                let newPrompt = PromptViewModel.StoredPrompt(
                    id: UUID(), // Always new ID
                    title: item.title,
                    content: item.content
                )
                merged.append(newPrompt)
                addedCount += 1
            }
        }
        return (merged, addedCount)
    }
}
