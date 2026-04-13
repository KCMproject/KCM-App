import SwiftUI

/// アプリ設定の永続化管理
/// UserDefaults + @AppStorage で使用されるキーを一元管理
enum AppSettings {
    static let tapToSwitchDayEnabled = "tapToSwitchDayEnabled"
    static let darkModeEnabled = "darkModeEnabled"
    static let pushNotificationsEnabled = "pushNotificationsEnabled"
    static let reminderEnabled = "reminderEnabled"
    static let tabBarConfiguration = "tabBarConfiguration"
}
