import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

// MARK: - Key-Accepting Panel

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Panel Controller (one per screen)

class NotchPanelController {
    let panel: NSPanel

    init(screen: NSScreen, state: NotchState, registry: AgentProviderRegistry, coordination: CoordinationEngine) {
        let size = NSSize(width: 420, height: 540)
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height

        panel = KeyablePanel(
            contentRect: NSRect(x: x, y: y, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar + 1
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let view = NotchView(state: state, coordination: coordination, screenID: screen.displayID, hasNotch: screen.hasNotch, registry: registry)
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.orderFrontRegardless()
    }

    func teardown() { panel.orderOut(nil) }
}

// MARK: - Screen Manager

class MultiScreenManager {
    var controllers: [CGDirectDisplayID: NotchPanelController] = [:]
    let state: NotchState
    let registry: AgentProviderRegistry
    let coordination: CoordinationEngine
    var clickMonitor: Any?

    init(state: NotchState, registry: AgentProviderRegistry, coordination: CoordinationEngine) {
        self.state = state
        self.registry = registry
        self.coordination = coordination
    }

    func setup() {
        refreshScreens()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshScreens() }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self, self.state.expandedScreenID != nil else { return }
            if !self.controllers.values.contains(where: { $0.panel.frame.contains(NSEvent.mouseLocation) }) {
                DispatchQueue.main.async { self.state.expandedScreenID = nil }
            }
        }
    }

    func refreshScreens() {
        let current = Set(NSScreen.screens.map { $0.displayID })
        for id in Set(controllers.keys).subtracting(current) {
            controllers[id]?.teardown(); controllers.removeValue(forKey: id)
        }
        for screen in NSScreen.screens where controllers[screen.displayID] == nil {
            controllers[screen.displayID] = NotchPanelController(screen: screen, state: state, registry: registry, coordination: coordination)
        }
    }
}

// MARK: - Hotkey: Cmd+Shift+N toggle

class HotkeyManager {
    init(state: NotchState) {
        let hotkeyID = EventHotKeyID(signature: OSType(0x4E434F44), id: 1)  // "NCOD"
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(cmdKey | shiftKey), hotkeyID, GetApplicationEventTarget(), 0, &ref)

        let statePtr = Unmanaged.passUnretained(state).toOpaque()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let s = Unmanaged<NotchState>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                if s.expandedScreenID != nil { s.expandedScreenID = nil }
                else {
                    let loc = NSEvent.mouseLocation
                    s.expandedScreenID = (NSScreen.screens.first { $0.frame.contains(loc) } ?? NSScreen.main)?.displayID
                }
            }
            return noErr
        }, 1, &eventType, statePtr, nil)
    }
}

// MARK: - Menu Bar Icon

class StatusItemManager {
    var statusItem: NSStatusItem!
    let state: NotchState
    let registry: AgentProviderRegistry

    init(state: NotchState, registry: AgentProviderRegistry) {
        self.state = state
        self.registry = registry
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                let path = NSBezierPath()
                let s = rect.width / 24.0
                // </> icon
                // Left bracket <
                path.move(to: NSPoint(x: 9 * s, y: rect.height - 5 * s))
                path.line(to: NSPoint(x: 3 * s, y: rect.height - 12 * s))
                path.line(to: NSPoint(x: 9 * s, y: rect.height - 19 * s))
                path.line(to: NSPoint(x: 10.5 * s, y: rect.height - 17.5 * s))
                path.line(to: NSPoint(x: 6 * s, y: rect.height - 12 * s))
                path.line(to: NSPoint(x: 10.5 * s, y: rect.height - 6.5 * s))
                path.close()
                // Right bracket >
                path.move(to: NSPoint(x: 15 * s, y: rect.height - 5 * s))
                path.line(to: NSPoint(x: 21 * s, y: rect.height - 12 * s))
                path.line(to: NSPoint(x: 15 * s, y: rect.height - 19 * s))
                path.line(to: NSPoint(x: 13.5 * s, y: rect.height - 17.5 * s))
                path.line(to: NSPoint(x: 18 * s, y: rect.height - 12 * s))
                path.line(to: NSPoint(x: 13.5 * s, y: rect.height - 6.5 * s))
                path.close()
                // Slash /
                path.move(to: NSPoint(x: 13.2 * s, y: rect.height - 4 * s))
                path.line(to: NSPoint(x: 14.2 * s, y: rect.height - 4 * s))
                path.line(to: NSPoint(x: 10.8 * s, y: rect.height - 20 * s))
                path.line(to: NSPoint(x: 9.8 * s, y: rect.height - 20 * s))
                path.close()
                NSColor.black.setFill(); path.fill()
                return true
            }
            img.isTemplate = true
            button.image = img
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle (⌘⇧N)", action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Install Hooks", action: #selector(installHooks), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Install MCP Server", action: #selector(installMCP), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Remove Hooks", action: #selector(removeHooks), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings...", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    var settingsWindow: NSWindow?

    @objc func toggle() {
        if state.expandedScreenID != nil { state.expandedScreenID = nil }
        else {
            let loc = NSEvent.mouseLocation
            state.expandedScreenID = (NSScreen.screens.first { $0.frame.contains(loc) } ?? NSScreen.main)?.displayID
        }
    }
    @objc func installHooks() {
        registry.claudeProvider()?.installHooks()
        registry.claudeProvider()?.writeHookScript()
    }
    @objc func installMCP() {
        let mgr = MCPServerManager()
        mgr.writeMCPServer()
        mgr.installMCPConfig()
        let alert = NSAlert()
        alert.messageText = "MCP Server Installed"
        alert.informativeText = "NotchCode Switchboard MCP server is now available.\n\nAgents can use tools like list_active_agents, claim_file, share_context to coordinate."
        alert.runModal()
    }
    @objc func removeHooks() { registry.claudeProvider()?.removeHooks() }
    @objc func openSettings() {
        if let w = settingsWindow, w.isVisible { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        w.title = "NotchCode Settings"
        w.contentView = NSHostingView(rootView: SettingsView())
        w.center()
        w.makeKeyAndOrderFront(nil)
        settingsWindow = w
    }
    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var screenManager: MultiScreenManager!
    var hotkeyManager: HotkeyManager!
    var statusItemManager: StatusItemManager!
    var registry: AgentProviderRegistry!
    var coordination: CoordinationEngine!
    var mcpManager: MCPServerManager!
    var fileWatcher: FileWatcher!
    let state = NotchState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up coordination engine
        coordination = CoordinationEngine()

        // Set up MCP server
        mcpManager = MCPServerManager()
        mcpManager.writeMCPServer()

        // Set up file watcher (detects external edits from Cursor, VS Code, etc.)
        fileWatcher = FileWatcher(coordination: coordination, state: state)
        fileWatcher.start()

        // Set up provider registry with coordination
        registry = AgentProviderRegistry(state: state)
        registry.register(ClaudeCodeProvider(state: state, coordination: coordination!))
        registry.register(CursorProvider(state: state, coordination: coordination!))

        screenManager = MultiScreenManager(state: state, registry: registry, coordination: coordination)
        screenManager.setup()
        hotkeyManager = HotkeyManager(state: state)
        statusItemManager = StatusItemManager(state: state, registry: registry)
        registry.startAll()

        // First launch: offer to install hooks
        if !UserDefaults.standard.bool(forKey: "setupComplete") {
            UserDefaults.standard.set(true, forKey: "setupComplete")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let alert = NSAlert()
                alert.messageText = "Welcome to NotchCode"
                alert.informativeText = "Install hooks and MCP server for multi-agent coordination?\n\nNotchCode Switchboard monitors Claude Code and Cursor, prevents file conflicts, and lets agents discover each other via MCP tools."
                alert.addButton(withTitle: "Install Everything")
                alert.addButton(withTitle: "Skip")
                if alert.runModal() == .alertFirstButtonReturn {
                    self.registry.claudeProvider()?.installHooks()
                    self.mcpManager.installMCPConfig()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        fileWatcher?.stop()
        registry?.cleanupAll()
    }
}
