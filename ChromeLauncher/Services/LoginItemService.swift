import Foundation
import ServiceManagement

enum LoginItemService {
    static func status() -> SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
        AppLog.loginItem.info("Login item status updated")
    }

    static func statusDescription(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return "Open Here is registered to open at login."
        case .requiresApproval:
            return "macOS needs your approval. Open System Settings → General → Login Items & Extensions and allow Open Here."
        case .notRegistered:
            return "Open Here will not open at login."
        case .notFound:
            return "macOS couldn’t find this copy of Open Here. Move the app to the Applications folder and try again."
        @unknown default:
            return "Login item status is unavailable."
        }
    }
}
