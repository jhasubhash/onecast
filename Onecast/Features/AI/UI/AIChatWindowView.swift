import SwiftUI

/// Which of the composer's own menu buttons is open; `AIChatDetailView` keeps at most one.
enum AIChatMenuKind: Hashable {
    case model
    case reasoning
    case tools
}

/// Each composer menu button's frame, so its popover opens exactly above it at any title width.
private struct AIChatMenuAnchors: PreferenceKey {
    static var defaultValue: [AIChatMenuKind: Anchor<CGRect>] { [:] }
    static func reduce(
        value: inout [AIChatMenuKind: Anchor<CGRect>],
        nextValue: () -> [AIChatMenuKind: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The window's detail pane; its menus are hosted here, above the transcript, by their buttons.
struct AIChatDetailView: View {
    let session: AIChatWindowSession

    @Environment(\.metrics) private var metrics
    @State private var openMenu: AIChatMenuKind?
    @State private var menuSelection = 0
    @State private var menuHeight: CGFloat = 0

    private var chat: AIChatState { session.chat }
    private var coordinator: AIChatCoordinator { session.coordinator }

    var body: some View {
        AIChatWindowView(
            session: session, openMenu: openMenu, toggleMenu: toggle, handleMenuKey: handleMenuKey)
            .environment(\.chatFindHighlight, session.find.highlight(in: chat.session.messages))
            .environment(
                \.chatTranscriptActions,
                ChatTranscriptActions(
                    choose: { coordinator.send($0) },
                    regenerate: coordinator.canRegenerate ? { coordinator.regenerate() } : nil))
            .overlay(alignment: .topTrailing) {
                if session.find.isSearching {
                    ChatFindCounter(session: session)
                        .padding(metrics.spacing.lg)
                }
            }
            // Click anywhere off an open menu closes it, as the palette's own scrim does.
            .overlay {
                if openMenu != nil {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onEnded { _ in openMenu = nil })
                        .onRightClick { openMenu = nil }
                }
            }
            .overlayPreferenceValue(AIChatMenuAnchors.self) { anchors in
                GeometryReader { proxy in
                    if let openMenu, let anchor = anchors[openMenu] {
                        let rect = proxy[anchor]
                        // Offset 8pt above its button once measured, and hidden until then.
                        menuView(for: openMenu)
                            .fixedSize()
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { menuHeight = $0 }
                            .offset(x: rect.minX, y: rect.minY - menuHeight - metrics.spacing.sm)
                            .opacity(menuHeight > 0 ? 1 : 0)
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    }
                }
            }
            .onChange(of: chat.session.id) { openMenu = nil }
    }

    private func content(for kind: AIChatMenuKind) -> PopoverMenuContent {
        switch kind {
        case .model: AIModelMenu.models(coordinator: coordinator)
        case .reasoning: AIModelMenu.reasoning(coordinator: coordinator, settings: session.aiSettings)
        case .tools: toolsMenu
        }
    }

    /// Every server this chat may reach, each switchable for this chat alone.
    private var toolsMenu: PopoverMenuContent {
        let scope = chat.toolScope
        var items = [
            PopoverMenuItem(
                title: "Use Tools", systemImage: scope.isEnabled ? "checkmark.circle.fill" : "circle"
            ) { coordinator.setToolsEnabled(!scope.isEnabled) }
        ]
        for (offset, server) in coordinator.toolServers.enumerated() {
            items.append(
                PopoverMenuItem(
                    title: server.title,
                    systemImage: scope.allows(server.slug) ? "checkmark.square" : "square",
                    isEnabled: scope.isEnabled, sectionTitle: offset == 0 ? "Servers" : nil
                ) { coordinator.toggleToolServer(server.slug) })
        }
        return PopoverMenuContent(header: "Tools", items: items)
    }

    @ViewBuilder
    private func menuView(for kind: AIChatMenuKind) -> some View {
        let content = content(for: kind)
        PopoverMenu(
            header: content.header, items: content.items, selection: $menuSelection,
            width: metrics.size.menuWidth,
            onActivate: { index in
                openMenu = nil
                content.items[index].action()
            })
    }

    private func toggle(_ kind: AIChatMenuKind) {
        guard openMenu != kind else {
            openMenu = nil
            return
        }
        openMenu = kind
        switch kind {
        case .model:
            let refresh = coordinator.prepareModelSwitcher()
            menuSelection = AIModelMenu.modelHighlight(
                coordinator: coordinator, settings: session.aiSettings)
            Task { @MainActor in
                await refresh.value
                guard openMenu == .model else { return }
                menuSelection = AIModelMenu.modelHighlight(
                    coordinator: coordinator, settings: session.aiSettings)
            }
        case .reasoning:
            menuSelection = AIModelMenu.reasoningHighlight(
                coordinator: coordinator, settings: session.aiSettings)
        case .tools:
            menuSelection = 0
        }
    }

    private func handleMenuKey(_ key: KeyEquivalent) {
        guard let openMenu else { return }
        let items = content(for: openMenu).items
        switch key {
        case .upArrow:
            menuSelection = max(0, menuSelection - 1)
        case .downArrow:
            menuSelection = min(max(items.count - 1, 0), menuSelection + 1)
        case .escape:
            self.openMenu = nil
        case .return:
            self.openMenu = nil
            if items.indices.contains(menuSelection) { items[menuSelection].action() }
        default:
            break
        }
    }
}

/// Its own text field, not the palette's: the window works while the palette shows anything else.
private struct AIChatWindowView: View {
    let session: AIChatWindowSession
    let openMenu: AIChatMenuKind?
    let toggleMenu: (AIChatMenuKind) -> Void
    let handleMenuKey: (KeyEquivalent) -> Void

    @Environment(\.metrics) private var metrics
    @State private var hostWindow: NSWindow?
    @State private var drafts: [UUID: String] = [:]
    @FocusState private var focused: Bool

    private var chat: AIChatState { session.chat }
    private var coordinator: AIChatCoordinator { session.coordinator }

    /// Each chat keeps its own unsent text, so switching chats never loses or leaks a draft.
    private var draft: Binding<String> {
        Binding(
            get: { drafts[chat.session.id] ?? "" },
            set: { drafts[chat.session.id] = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            AIChatView(
                chat: chat, settings: session.aiSettings, availability: coordinator.availability,
                showReasoning: coordinator.activeAssistant?.showReasoning
                    ?? session.aiSettings.showReasoning,
                onConfigure: coordinator.showSettings, onAppear: coordinator.prepareForChat)
            composer
        }
        .background(WindowReader { hostWindow = $0 })
        // Above the composer's own controls, so it still fires once a menu button holds focus.
        .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape], phases: .down) { press in
            guard openMenu != nil else { return .ignored }
            handleMenuKey(press.key)
            return .handled
        }
        .onAppear { focused = true }
        .onChange(of: chat.session.id) { focused = true }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            textField
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.sm)
                .background(fieldShape.fill(Theme.Colors.cardFill))
                .overlay(fieldShape.strokeBorder(Theme.Colors.cardStroke, lineWidth: Theme.Size.hairline))
            statusRow
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.top, metrics.spacing.md)
        .padding(.bottom, metrics.spacing.lg)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: Theme.Size.hairline)
        }
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.radius.barControl, style: .continuous)
    }

    /// Its own prompt overlay: SwiftUI's placeholder distorts the caret on a vertical-axis field.
    private var textField: some View {
        TextField("", text: draft, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...8)
            .font(.system(size: 16))
            .tint(Theme.Colors.textPrimary)
            .focused($focused)
            .background(alignment: .topLeading) {
                if draft.wrappedValue.isEmpty {
                    Text("Ask anything…")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .allowsHitTesting(false)
                }
            }
            // Plain ↵ sends, or stops a streaming reply; ⇧↵ breaks the line instead.
            .onKeyPress(keys: [.return], phases: .down) { press in
                guard openMenu == nil else { return .ignored }
                if press.modifiers == .shift {
                    let editor = hostWindow?.firstResponder as? NSTextView
                    editor?.insertText("\n", replacementRange: editor?.selectedRange() ?? NSRange())
                    return .handled
                }
                guard press.modifiers.isEmpty else { return .ignored }
                send()
                return .handled
            }
    }

    private var statusRow: some View {
        HStack(spacing: metrics.spacing.xs) {
            AIModelButton(
                title: coordinator.selectedModelTitle, icon: coordinator.selectedModelIcon,
                isOpen: openMenu == .model, action: { toggleMenu(.model) }
            )
            .anchorPreference(key: AIChatMenuAnchors.self, value: .bounds) { [.model: $0] }
            if !coordinator.reasoningEfforts.isEmpty {
                AIReasoningButton(
                    title: coordinator.selectedReasoningTitle, isOpen: openMenu == .reasoning,
                    action: { toggleMenu(.reasoning) }
                )
                .anchorPreference(key: AIChatMenuAnchors.self, value: .bounds) { [.reasoning: $0] }
            }
            if !coordinator.toolServers.isEmpty {
                HeaderMenuButton(
                    title: toolsTitle, systemImage: "wrench.and.screwdriver",
                    isOpen: openMenu == .tools, help: "Choose this chat's tools",
                    action: { toggleMenu(.tools) }
                )
                .fixedSize(horizontal: true, vertical: false)
                .anchorPreference(key: AIChatMenuAnchors.self, value: .bounds) { [.tools: $0] }
            }
            Spacer(minLength: 0)
            ChatContextGauge(report: coordinator.contextReport)
        }
    }

    private var toolsTitle: String {
        let scope = chat.toolScope
        guard scope.isEnabled else { return "Tools Off" }
        let servers = coordinator.toolServers
        let active = servers.filter { scope.allows($0.slug) }.count
        return active == servers.count ? "All Tools" : "\(active) of \(servers.count) Tools"
    }

    private func send() {
        if chat.isStreaming {
            coordinator.stopResponse()
            return
        }
        guard coordinator.send(draft.wrappedValue) else { return }
        draft.wrappedValue = ""
    }
}

/// "3 of 12" with chevrons, over the transcript's corner while Find has a query.
private struct ChatFindCounter: View {
    @Environment(\.metrics) private var metrics
    let session: AIChatWindowSession

    var body: some View {
        let messages = session.chat.session.messages
        let count = session.find.occurrences(in: messages).count
        HStack(spacing: metrics.spacing.sm) {
            Text(count == 0 ? "No matches" : "\(session.find.current % count + 1) of \(count)")
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textSecondary)
            Button { session.stepFind(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(count == 0)
            Button { session.stepFind(1) } label: { Image(systemName: "chevron.down") }
                .disabled(count == 0)
        }
        .buttonStyle(.plain)
        .font(metrics.typography.rowTrailing)
        .padding(.horizontal, metrics.spacing.lg)
        .padding(.vertical, metrics.spacing.sm)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline))
    }
}

/// A ring of how full the next message's history is; hovering lists what it carries.
private struct ChatContextGauge: View {
    @Environment(\.metrics) private var metrics
    let report: ChatContextReport
    @State private var hovered = false

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            ZStack {
                Circle().stroke(Theme.Colors.border, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: min(report.fill, 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: metrics.scaled(14), height: metrics.scaled(14))
            Text("\(Int((min(report.fill, 1) * 100).rounded()))%")
                .monospacedDigit()
                .font(metrics.typography.keyCap)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .overlay(alignment: .bottomTrailing) {
            if hovered {
                card
                    .fixedSize()
                    .offset(y: -metrics.scaled(24))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: Theme.Duration.tooltip), value: hovered)
    }

    private var tint: Color {
        if report.fill >= 1 { return Theme.Colors.destructive }
        if report.fill >= 0.8 { return .orange }
        return Theme.Colors.textSecondary
    }

    private var card: some View {
        let bytes = ByteCountFormatStyle(style: .file)
        return VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            Text("Next message").font(metrics.typography.sectionHeader)
            row("Model", report.modelTitle)
            row(
                "History",
                "\(Int64(report.historyBytes).formatted(bytes)) of \(Int64(report.budget).formatted(bytes))")
            row("Messages", "\(report.sentMessages) of \(report.totalMessages) sent")
            if report.stagedFiles > 0 { row("Attached", "\(report.stagedFiles)") }
            if report.toolServers > 0 { row("MCP servers", "\(report.toolServers)") }
            if let tokens = report.totalTokens { row("Last reply", "\(tokens.formatted()) tokens") }
        }
        .font(metrics.typography.keyCap)
        .padding(metrics.spacing.lg)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: metrics.radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.card)
                .strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: metrics.spacing.xl)
            Text(value).foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}
