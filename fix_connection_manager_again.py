import sys

filepath = 'Sources/RepoPrompt/Infrastructure/MCP/MCPConnectionManager.swift'
with open(filepath, 'r') as f:
    content = f.read()

search_block = """            do {
                let handle = try await runtime.routingCoordinator.resolveReadContext(connection: registration)
                workspaceID = handle.context.workspaceID
                workspaceRevision = handle.workspaceRevision
                if let workspace = await runtime.contextStore.workspaceSnapshot(handle.context.workspaceID) {
                    authorizedCanonicalRoots = Set(workspace.document.metadata.repoPaths.compactMap {
                        DomainMutationPathFence.canonicalPath($0)
                    })
                }
            } catch {
                // Registration is authoritative only together with a resolved domain context.
                // Never normalize stale, unbound, or unavailable routing into an empty root set.
                hasAuthoritativeRoutingContext = false
            }"""

replace_block = """            do {
                let handle = try await runtime.routingCoordinator.resolveReadContext(connection: registration)
                workspaceID = handle.context.workspaceID
                workspaceRevision = handle.workspaceRevision
                if let workspace = await runtime.contextStore.workspaceSnapshot(handle.context.workspaceID) {
                    authorizedCanonicalRoots = Set(workspace.document.metadata.repoPaths.compactMap {
                        DomainMutationPathFence.canonicalPath($0)
                    })
                } else {
                    // Re-instate throwing so tests expect contextUnavailable
                    hasAuthoritativeRoutingContext = false
                    throw DomainReadContextResolutionError.contextUnavailable
                }
            } catch {
                // Registration is authoritative only together with a resolved domain context.
                // Never normalize stale, unbound, or unavailable routing into an empty root set.
                hasAuthoritativeRoutingContext = false
            }"""

if search_block in content:
    content = content.replace(search_block, replace_block)
    with open(filepath, 'w') as f:
        f.write(content)
    print("Patched MCPConnectionManager.swift")
else:
    print("Could not find search block in MCPConnectionManager.swift")
