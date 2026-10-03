import Foundation
import RepoPromptFoundation

protocol FileSystemItem: Identifiable, Equatable, Sendable {
    var id: UUID { get }
    var name: String { get }
    var path: String { get }
    var modificationDate: Date { get }
}

struct Folder: FileSystemItem {
    let id: UUID
    let name: String
    let path: String
    let modificationDate: Date

    init(id: UUID = UUID(), name: String, path: String, modificationDate: Date) {
        self.id = id
        self.name = name
        self.path = path
        self.modificationDate = modificationDate
    }

    static func == (lhs: Folder, rhs: Folder) -> Bool {
        lhs.path == rhs.path
    }
}

extension FileSystemItem {
    func relativePath(rootPath: String) -> String {
        RelativePath.from(absolutePath: path, rootPath: rootPath)
    }
}

struct File: FileSystemItem {
    let id: UUID
    let name: String
    let path: String
    let modificationDate: Date

    init(id: UUID = UUID(), name: String, path: String, modificationDate: Date) {
        self.id = id
        self.name = name
        self.path = path
        self.modificationDate = modificationDate
    }

    static func == (lhs: File, rhs: File) -> Bool {
        lhs.path == rhs.path
    }
}

enum FileTreeItem: Identifiable {
    case folder(String, [FileViewModel])
    case file(FileViewModel)

    var id: String {
        switch self {
        case let .folder(path, _):
            "folder_\(path)"
        case let .file(file):
            "file_\(file.id)"
        }
    }

    var path: String {
        switch self {
        case let .folder(name, _): name
        case let .file(file): file.relativePath
        }
    }
}
