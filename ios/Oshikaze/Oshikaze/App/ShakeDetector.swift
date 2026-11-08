import UIKit

extension Notification.Name {
    /// スマホが振られた
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

/// 振る操作は UIKit の responder chain でしか受け取れないので、ウインドウで受けて通知に変える
extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
