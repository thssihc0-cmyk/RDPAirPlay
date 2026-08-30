import UIKit

/// 远程会话期间禁止自动锁屏
@MainActor
enum ScreenWakeLock {
    private static var holdCount = 0

    static func acquire() {
        holdCount += 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func release() {
        holdCount = max(0, holdCount - 1)
        if holdCount == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// 离开会话页时的兜底恢复
    static func reset() {
        holdCount = 0
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
