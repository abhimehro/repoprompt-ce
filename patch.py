import re

with open('./Tests/RepoPromptTests/ContextBuilder/ContextBuilderNestedMCPFailureTests.swift', 'r') as f:
    content = f.read()

replacement = """                    await gate.release()
                    await manager.debugAwaitCodeStructureSettlementDrain(
                        windowID: fixture.contextA.window.windowID
                    )

                    // Wait for the detached event to be emitted
                    let settled = await AsyncTestCondition.waitUntil {
                        let events = recorder.snapshot()
                        return events.contains {
                            $0.connectionID == nestedConnectionID &&
                            $0.toolName == MCPWindowToolName.readFile &&
                            $0.phase == .detachedSettled
                        }
                    }
                    XCTAssertTrue(settled)

                    let settledNestedEvents = recorder.snapshot().filter {
                        $0.connectionID == nestedConnectionID &&
                            $0.toolName == MCPWindowToolName.readFile
                    }
                    XCTAssertTrue(settledNestedEvents.contains { $0.phase == .detachedSettled })"""

content = content.replace("""                    await gate.release()
                    await manager.debugAwaitCodeStructureSettlementDrain(
                        windowID: fixture.contextA.window.windowID
                    )

                    // Wait for the detached event to be emitted
                    let settled = await PersistentMCPTestFixture.waitUntil {
                        let events = recorder.snapshot()
                        return events.contains {
                            $0.connectionID == nestedConnectionID &&
                            $0.toolName == MCPWindowToolName.readFile &&
                            $0.phase == .detachedSettled
                        }
                    }
                    XCTAssertTrue(settled)

                    let settledNestedEvents = recorder.snapshot().filter {
                        $0.connectionID == nestedConnectionID &&
                            $0.toolName == MCPWindowToolName.readFile
                    }
                    XCTAssertTrue(settledNestedEvents.contains { $0.phase == .detachedSettled })""", replacement)

with open('./Tests/RepoPromptTests/ContextBuilder/ContextBuilderNestedMCPFailureTests.swift', 'w') as f:
    f.write(content)
