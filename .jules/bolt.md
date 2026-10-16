## 2025-09-24 - Pre-compile NSRegularExpression Instances
**Learning:** Re-compiling `NSRegularExpression` objects on every call to string sanitization helpers creates unnecessary allocation and compilation overhead in hot paths like `MCPTerminalRecord.privacySafeText`.
**Action:** Pre-compile static regex instances into static constants on the enclosing type for reuse across invocations.
