import Foundation

extension CLIProcessConfiguration {
    package mutating func ensureAdditionalPaths(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        var seen = Set(additionalPaths)
        for path in paths where seen.insert(path).inserted {
            additionalPaths.append(path)
        }
    }
}
