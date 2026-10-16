import Foundation

/// The window server's private Spaces calls; nothing public reads or sets a process's desktops.
struct SkyLight {
    /// One display's spaces, in the window server's display order.
    struct ManagedDisplay: Sendable {
        let spaceUUIDs: [String]
        let currentSpaceUUID: String
        let currentSpaceID: UInt64
    }

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias AssignToAllSpaces = @convention(c) (Int32, pid_t) -> Int32
    private typealias AssignToSpace = @convention(c) (Int32, pid_t, UInt64) -> Int32

    private let connection: Int32
    private let copyManagedDisplaySpaces: CopyManagedDisplaySpaces
    private let processAssignToAllSpaces: AssignToAllSpaces
    private let processAssignToSpace: AssignToSpace

    init?() {
        guard
            let handle = dlopen(
                "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        else { return nil }
        func symbol<Function>(_ name: String) -> Function? {
            dlsym(handle, name).map { unsafeBitCast($0, to: Function.self) }
        }
        guard
            let mainConnectionID: MainConnectionID = symbol("SLSMainConnectionID"),
            let copyManagedDisplaySpaces: CopyManagedDisplaySpaces = symbol(
                "SLSCopyManagedDisplaySpaces"),
            let assignToAllSpaces: AssignToAllSpaces = symbol("SLSProcessAssignToAllSpaces"),
            let assignToSpace: AssignToSpace = symbol("SLSProcessAssignToSpace")
        else { return nil }
        connection = mainConnectionID()
        self.copyManagedDisplaySpaces = copyManagedDisplaySpaces
        processAssignToAllSpaces = assignToAllSpaces
        processAssignToSpace = assignToSpace
    }

    func managedDisplays() -> [ManagedDisplay] {
        let displays =
            copyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]] ?? []
        return displays.compactMap { display in
            guard let current = display["Current Space"] as? [String: Any],
                let currentID = current["id64"] as? UInt64
            else { return nil }
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            return ManagedDisplay(
                spaceUUIDs: spaces.compactMap { $0["uuid"] as? String },
                currentSpaceUUID: current["uuid"] as? String ?? "",
                currentSpaceID: currentID)
        }
    }

    func assignToAllSpaces(_ pid: pid_t) {
        _ = processAssignToAllSpaces(connection, pid)
    }

    /// Space 0 drops the assignment, so the process's windows stay where they open.
    func assign(_ pid: pid_t, toSpace spaceID: UInt64) {
        _ = processAssignToSpace(connection, pid, spaceID)
    }
}
