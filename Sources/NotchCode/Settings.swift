import Foundation
import SwiftUI

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("monitorClaude") var monitorClaude: Bool = true
    @AppStorage("monitorCursor") var monitorCursor: Bool = true
    @AppStorage("autoResolve") var autoResolve: Bool = false
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NotchCode Settings")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)

            GroupBox("Agents") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Monitor Claude Code", isOn: $settings.monitorClaude)
                    Toggle("Monitor Cursor", isOn: $settings.monitorCursor)
                }
                .padding(6)
            }

            GroupBox("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { enabled in
                        if enabled { installLaunchAgent() } else { removeLaunchAgent() }
                    }
                    .padding(6)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 360, height: 240)
    }
}

func installLaunchAgent() {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let execPath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key><string>com.notchcode.app</string>
        <key>ProgramArguments</key><array><string>\(execPath)</string></array>
        <key>RunAtLoad</key><true/>
    </dict>
    </plist>
    """
    try? plist.write(to: dir.appendingPathComponent("com.notchcode.app.plist"), atomically: true, encoding: .utf8)
}

func removeLaunchAgent() {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.notchcode.app.plist")
    try? FileManager.default.removeItem(at: path)
}
