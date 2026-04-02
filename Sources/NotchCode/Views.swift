import SwiftUI

// MARK: - Collapsed View

struct CollapsedView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var coordination: CoordinationEngine
    let hasNotch: Bool

    var body: some View {
        HStack(spacing: 0) {
            // During conflicts, replace the app icon with a warning icon
            if !coordination.pendingDecisions.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: hasNotch ? 16 : 14))
                    .foregroundColor(.red)
                    .fixedSize()
                    .padding(.leading, hasNotch ? 20 : 14)

                Spacer(minLength: 8)

                if let d = coordination.pendingDecisions.first {
                    Text(d.fileName)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.red.opacity(0.9))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                    .padding(.trailing, hasNotch ? 16 : 14)
            } else {
                Group {
                    let types = state.activeAgentTypes
                    if types.count == 1, let type = types.first {
                        agentIcon(for: type, size: hasNotch ? 18 : 16)
                    } else {
                        NotchCodeIcon()
                            .fill(Color.white.opacity(0.7))
                            .frame(width: hasNotch ? 18 : 16, height: hasNotch ? 18 : 16)
                    }
                }
                .fixedSize()
                .padding(.leading, hasNotch ? 20 : 14)

                Spacer(minLength: 8)
            }

            if coordination.pendingDecisions.isEmpty, state.hasActiveWork, let session = state.activeSession {
                if session.isWaitingForUser {
                    Text("Waiting for you")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(session.agentType.accentColor).lineLimit(1)
                } else {
                    Text(session.statusMessage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.65)).lineLimit(1)
                }

                if state.sessions.count > 1 {
                    HStack(spacing: 3) {
                        ForEach(Array(state.sessions.enumerated()), id: \.1.id) { idx, s in
                            Circle().fill(idx == state.activeSessionIndex ? .white : progressColor(s).opacity(0.5))
                                .frame(width: 3.5, height: 3.5)
                        }
                    }.padding(.leading, 4)
                }

                Spacer(minLength: 8)

                ProgressRing(progress: session.progress, size: hasNotch ? 16 : 14, lineWidth: 2, color: progressColor(session))
                    .fixedSize()
                    .padding(.trailing, hasNotch ? 16 : 14)
            } else {
                Spacer(minLength: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Conflict Visualization (two agent dots with red line + filename)

struct ConflictVisual: View {
    let decision: PendingDecision
    let onKeepOwner: () -> Void
    let onLetIn: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Visual: [Owner] ——red line—— filename ——red line—— [Modifier]
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    agentIcon(for: decision.ownerAgent, size: 16)
                    Text(decision.ownerSession)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(decision.ownerAgent.accentColor.opacity(0.8))
                        .lineLimit(1)
                    Text("owns file")
                        .font(.system(size: 6))
                        .foregroundColor(.white.opacity(0.25))
                }
                .frame(width: 60)

                VStack(spacing: 3) {
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.red.opacity(0.5)).frame(height: 1.5)
                        Text(decision.fileName)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                        Rectangle().fill(Color.red.opacity(0.5)).frame(height: 1.5)
                    }
                    if decision.isExternal {
                        Text("external edit detected")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(.red.opacity(0.6))
                    }
                }

                VStack(spacing: 2) {
                    agentIcon(for: decision.blockedAgent, size: 16)
                    Text(decision.blockedSession)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(decision.blockedAgent.accentColor.opacity(0.8))
                        .lineLimit(1)
                    Text(decision.isExternal ? "edited" : "blocked")
                        .font(.system(size: 6))
                        .foregroundColor(.red.opacity(0.5))
                }
                .frame(width: 60)
            }

            // Explainer
            Text("\(decision.blockedSession) tried to edit \(decision.fileName) but \(decision.ownerSession) is already working on it")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            // Action buttons
            HStack(spacing: 8) {
                Button(action: onKeepOwner) {
                    HStack(spacing: 4) {
                        agentIcon(for: decision.ownerAgent, size: 9)
                        Text(decision.isExternal ? "Revert to \(decision.ownerSession)" : "Keep \(decision.ownerSession)")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(decision.ownerAgent.accentColor)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(decision.ownerAgent.accentColor.opacity(0.12))
                    .cornerRadius(6)
                }.buttonStyle(.plain)

                Button(action: onLetIn) {
                    HStack(spacing: 4) {
                        agentIcon(for: decision.blockedAgent, size: 9)
                        Text(decision.isExternal ? "Accept \(decision.blockedSession)" : "Let \(decision.blockedSession) in")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(decision.blockedAgent.accentColor)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(decision.blockedAgent.accentColor.opacity(0.12))
                    .cornerRadius(6)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.red.opacity(0.04))
    }
}

// MARK: - Stats Bar

struct StatsBar: View {
    let stats: SwitchboardStats

    var body: some View {
        HStack(spacing: 14) {
            Label("\(stats.conflictsPrevented) conflicts", systemImage: "shield.fill")
                .foregroundColor(.red.opacity(0.5))
            Label("\(stats.filesCoordinated) files", systemImage: "lock.fill")
                .foregroundColor(.yellow.opacity(0.5))
            Label("\(stats.contextShared) shared", systemImage: "arrow.triangle.2.circlepath")
                .foregroundColor(.blue.opacity(0.5))
            Spacer()
        }
        .font(.system(size: 8, weight: .medium, design: .monospaced))
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(Color.white.opacity(0.02))
    }
}

// MARK: - Expanded View

struct ExpandedView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var coordination: CoordinationEngine
    let hasNotch: Bool
    var onCollapse: () -> Void = {}
    var registry: AgentProviderRegistry?
    @State private var messageText: String = ""
    @State private var autoResolve: Bool = AppSettings.shared.autoResolve

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Button(action: onCollapse) {
                    NotchCodeIcon().fill(Color.white.opacity(0.8)).frame(width: 20, height: 20)
                }.buttonStyle(.plain)

                Text("Switchboard").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                Spacer()

                if let session = state.activeSession {
                    ProgressRing(progress: session.progress, size: 20, lineWidth: 2.5, color: progressColor(session))
                        .overlay(Text("\(Int(session.progress * 100))").font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.5)))
                }

                Button(action: onCollapse) {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture { onCollapse() }
            .padding(.horizontal, 16).padding(.top, hasNotch ? 12 : 10).padding(.bottom, 6)

            // Stats bar + auto-resolve toggle
            let s = coordination.stats
            if s.conflictsPrevented + s.filesCoordinated + s.contextShared > 0 {
                HStack(spacing: 0) {
                    StatsBar(stats: s)
                    Toggle("Auto-resolve", isOn: $autoResolve)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.trailing, 16)
                        .onChange(of: autoResolve) { on in
                            AppSettings.shared.autoResolve = on
                        }
                }
            }

            // Conflict visualizations
            ForEach(coordination.pendingDecisions) { decision in
                ConflictVisual(
                    decision: decision,
                    onKeepOwner: {
                        if decision.isExternal {
                            coordination.resolveExternalConflict(id: decision.id, keepOwner: true)
                        } else {
                            coordination.writeDecision(requestId: decision.id, approved: false)
                        }
                    },
                    onLetIn: {
                        if decision.isExternal {
                            coordination.resolveExternalConflict(id: decision.id, keepOwner: false)
                        } else {
                            coordination.writeDecision(requestId: decision.id, approved: true)
                        }
                    }
                )
            }

            // Session list (when multiple)
            if state.sessions.count > 1 {
                Divider().background(Color.white.opacity(0.06))
                VStack(spacing: 4) {
                    ForEach(Array(state.sessions.enumerated()), id: \.1.id) { idx, session in
                        Button { state.activeSessionIndex = idx } label: {
                            HStack(spacing: 6) {
                                agentIcon(for: session.agentType, size: 10)
                                Circle().fill(session.isWaitingForUser ? session.agentType.accentColor : progressColor(session)).frame(width: 6, height: 6)
                                Text(session.name).font(.system(size: 11, weight: idx == state.activeSessionIndex ? .semibold : .regular))
                                    .foregroundColor(idx == state.activeSessionIndex ? .white : .white.opacity(0.5))
                                Spacer()
                                Text(session.duration).font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.25))
                                ProgressRing(progress: session.progress, size: 12, lineWidth: 1.5, color: progressColor(session))
                            }
                            .padding(.vertical, 2).padding(.horizontal, 4)
                            .background(idx == state.activeSessionIndex ? Color.white.opacity(0.06) : Color.clear)
                            .cornerRadius(6)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }

            Divider().background(Color.white.opacity(0.06))

            // Active session content
            if let session = state.activeSession {
                // Agent type bar
                HStack(spacing: 6) {
                    agentIcon(for: session.agentType, size: 12)
                    Text(session.agentType.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(session.agentType.accentColor)
                    if !coordination.fileLocks.isEmpty {
                        Image(systemName: "lock.fill").font(.system(size: 7)).foregroundColor(.yellow.opacity(0.5))
                        Text("\(coordination.fileLocks.count)").font(.system(size: 8)).foregroundColor(.yellow.opacity(0.4))
                    }
                    Spacer()
                    Text(session.statusMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
                .padding(.horizontal, 16).padding(.vertical, 6)

                // Claude reasoning
                if session.agentType == .claudeCode, let reasoning = session.lastReasoning {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "brain").font(.system(size: 9)).foregroundColor(claudeOrange.opacity(0.6)).padding(.top, 2)
                        Text(reasoning).font(.system(size: 11)).foregroundColor(.white.opacity(0.7)).lineLimit(3)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.white.opacity(0.03))
                }

                // Token stats
                if session.inputTokens > 0 {
                    HStack(spacing: 12) {
                        Label(session.tokenSummary, systemImage: "number")
                        Label(session.duration, systemImage: "clock")
                        Spacer()
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.horizontal, 16).padding(.vertical, 4)
                }

                // Waiting indicator
                if session.isWaitingForUser {
                    HStack(spacing: 6) {
                        Circle().fill(session.agentType.accentColor).frame(width: 6, height: 6)
                        Text("\(session.agentType.displayName) is waiting for your input")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(session.agentType.accentColor)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(session.agentType.accentColor.opacity(0.08))
                }

                Divider().background(Color.white.opacity(0.06))

                // Task list
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(session.tasks) { task in
                            HStack(spacing: 6) {
                                Image(systemName: task.status.icon).font(.system(size: 10)).foregroundColor(task.status.color).frame(width: 14)
                                Text(task.title).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.8)).lineLimit(1)
                                Spacer()
                                Text(task.elapsed).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.25))
                                Text(task.status.label).font(.system(size: 9, weight: .semibold)).foregroundColor(task.status.color)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxHeight: 160)
                .padding(.horizontal, 16).padding(.vertical, 6)

                // Output
                if let response = session.lastResponse, !response.isEmpty {
                    Divider().background(Color.white.opacity(0.06))
                    Text(response)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Color.white.opacity(0.03))
                }

                // Bottom input
                Divider().background(Color.white.opacity(0.06))
                if session.agentType == .claudeCode {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal").font(.system(size: 10)).foregroundColor(.white.opacity(0.3))
                            ZStack(alignment: .leading) {
                                if messageText.isEmpty {
                                    Text("Message Claude, Enter to copy...")
                                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.3))
                                }
                                TextField("", text: $messageText)
                                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundColor(.white)
                                    .onSubmit { send() }
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.white.opacity(0.1)).cornerRadius(8)

                        Button(action: send) {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
                                .foregroundColor(messageText.trimmingCharacters(in: .whitespaces).isEmpty ? .white.opacity(0.15) : claudeOrange)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                } else {
                    Button {
                        if let cursor = registry?.provider(for: .cursor) as? CursorProvider {
                            cursor.openInCursor(path: session.projectPath)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.forward.app").font(.system(size: 11))
                            Text("Open in Cursor").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(cursorPurple)
                        .padding(.vertical, 8).frame(maxWidth: .infinity)
                        .background(cursorPurple.opacity(0.1)).cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
        }
    }

    func send() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        messageText = ""
        registry?.claudeProvider()?.sendToTerminal(text)
    }
}

// MARK: - Root Notch View

struct NotchView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var coordination: CoordinationEngine
    let screenID: CGDirectDisplayID
    let hasNotch: Bool
    var registry: AgentProviderRegistry?

    @State private var isHovering = false
    @State private var showExpanded = false

    var isExpanded: Bool { state.expandedScreenID == screenID }
    var accentColor: Color { state.activeSession?.agentType.accentColor ?? claudeOrange }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if showExpanded {
                    ExpandedView(state: state, coordination: coordination, hasNotch: hasNotch, onCollapse: { collapse() }, registry: registry)
                        .frame(width: 390)
                        .transition(.opacity)
                } else {
                    CollapsedView(state: state, coordination: coordination, hasNotch: hasNotch)
                        .frame(height: hasNotch ? 38 : 28)
                        .frame(width: hasNotch ? 320 : (state.hasActiveWork ? 220 : 130))
                        .contentShape(Rectangle())
                        .onTapGesture { expand() }
                }
            }
            .clipShape(notchShape)
            .background(notchShape.fill(Color.black))
            .overlay(borderOverlay)
            .shadow(color: (hasNotch && !showExpanded) ? .clear : .black.opacity(0.3), radius: 5, y: 2)
            .animation(.easeInOut(duration: 0.25), value: showExpanded)
            .animation(.easeInOut(duration: 0.15), value: state.hasActiveWork)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { isHovering = $0 }
        .onChange(of: isExpanded) { expanded in
            withAnimation(.easeInOut(duration: expanded ? 0.25 : 0.2)) { showExpanded = expanded }
        }
        .onChange(of: coordination.pendingDecisions.count) { count in
            // Auto-expand the notch on the mouse's screen when a conflict arrives
            if count > 0 && state.expandedScreenID == nil {
                let loc = NSEvent.mouseLocation
                if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(loc) }),
                   mouseScreen.displayID == screenID {
                    expand()
                }
            }
        }
    }

    var notchShape: NotchCollapsedShape {
        NotchCollapsedShape(bottomRadius: showExpanded ? 18 : (hasNotch ? 18 : 12))
    }

    @ViewBuilder var borderOverlay: some View {
        if hasNotch && !showExpanded { Color.clear }
        else { notchShape.stroke(isHovering ? accentColor.opacity(0.2) : Color.white.opacity(0.04), lineWidth: 0.5) }
    }

    func expand() { state.expandedScreenID = screenID }
    func collapse() { state.expandedScreenID = nil }
}
