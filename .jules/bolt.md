## 2025-08-02 - Avoid massive allocations in Swift data structs
**Learning:** Instantiating `ISO8601DateFormatter` is very expensive in Swift. Finding hundreds of instances in a struct holding static data (`Changelog.swift`) means we incur that instantiation cost whenever the data is loaded (which causes a measurable hit, even though it's static/lazy because the class has ~215 instances to build during initial parse).
**Action:** Extract `ISO8601DateFormatter` into a static property on the wrapping class (`Changelog.sharedFormatter`) and reuse it across all data entries.
