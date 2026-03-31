import CodexBarCore
import ServiceManagement

enum LaunchAtLoginManager {
    private static let log = CodexBarLog.logger(LogCategories.launchAtLogin)

    private static let isRunningTests: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["TESTING_LIBRARY_VERSION"] != nil { return true }
        if env["SWIFT_TESTING"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }()

    /// Called on every launch to reconcile the persisted preference with the
    /// actual SMAppService state. Only mutates if there is a mismatch, avoiding
    /// the duplicate-login-item bug caused by re-registering with ad-hoc signing.
    static func reconcile(_ desired: Bool) {
        if self.isRunningTests { return }
        let service = SMAppService.mainApp
        let current = service.status
        if desired, current != .enabled {
            self.setEnabled(true)
        } else if !desired, current == .enabled {
            self.setEnabled(false)
        }
    }

    /// Unconditionally register or unregister. Use for explicit user toggles.
    static func setEnabled(_ enabled: Bool) {
        if self.isRunningTests { return }
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            self.log.error("Failed to update login item: \(error)")
        }
    }
}
