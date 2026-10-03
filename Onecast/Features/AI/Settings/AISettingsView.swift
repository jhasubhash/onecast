import SwiftUI

struct AISettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AISettingsStore.self) private var settings
    @Environment(AppSettings.self) private var appSettings
    @Environment(ChatGPTSubscriptionManager.self) private var subscription
    @Environment(InstalledAIManager.self) private var installedAI

    @State private var providersPresented = false

    var body: some View {
        @Bindable var appSettings = appSettings
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $appSettings.aiEnabled) {
                    SettingsRowTitle(.aiAI, "Enable AI")
                    Text("Chat with the model you choose; nothing is loaded or sent until it is on.")
                }
                SettingsRow(
                    title: "Providers", subtitle: providerSummary, anchor: .aiProviders
                ) {
                    Button("Manage…") { providersPresented = true }
                }
            } header: {
                SettingsSectionHeader(.aiAI)
            }

            FeatureCommandsSection(owner: .ai, anchor: .aiCommands)
                .settingsEnabled(appSettings.aiEnabled)

            Group {
                AssistantsSettingsSection()
                SkillsSettingsSection()
                defaultModelSection
                chatSection
                conversationsSection
                systemPromptSection
                MCPSettingsSection()
            }
            .settingsEnabled(appSettings.aiEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.ai)
        .sheet(isPresented: $providersPresented) {
            AIProvidersPanel(onDone: { providersPresented = false })
        }
        .onAppear {
            core.applyInstalledAILifecycle()
        }
        // Switched on with the pane already open, provider status would otherwise stay empty.
        .onChange(of: settings.enabledInstalledProviders) {
            core.applyInstalledAILifecycle()
            syncSelection()
        }
        .onChange(of: subscription.models) { syncSelection() }
        .onChange(of: subscription.phase) { syncSelection() }
        .onChange(of: installedAI.statuses) { syncSelection() }
    }

    private var defaultModelSection: some View {
        Section {
            // A Mac with nothing configured is the one that needs telling its free route is off.
            if let reason = appleIntelligenceReason {
                Label(reason, systemImage: "apple.intelligence")
                    .foregroundStyle(.secondary)
            }
            AIModelSelectionRows(
                selection: settings.defaultModel,
                select: { $0.map(settings.select) },
                modelLabel: {
                    SettingsRowTitle(.aiDefault, "Default model")
                    Text("Used by Onecast features unless they ask you to choose another model.")
                },
                effortLabel: {
                    SettingsRowTitle(.aiDefault, "Reasoning effort")
                    Text("Applied when the default model supports reasoning effort.")
                }
            )
        } header: {
            SettingsSectionHeader(.aiDefault)
        } footer: {
            Text(defaultModelFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var defaultModelFooter: String {
        if settings.defaultModel?.isOnDevice == true {
            return "Apple Intelligence runs on this Mac. No key, no account, and nothing leaves it."
        }
        return settings.defaultModel == nil
            ? "Turn on Apple Intelligence, or add a provider above."
            : "Onecast contacts only the selected provider when an AI feature runs."
    }

    /// Why the on-device route is missing from the picker, or `nil` when it is there.
    private var appleIntelligenceReason: String? {
        guard settings.isRouteEnabled(.appleIntelligence) else {
            return "Apple Intelligence is disabled in AI Providers."
        }
        return settings.isAppleIntelligenceAvailable()
            ? nil : AppleIntelligenceProvider.status().message
    }

    private var providerSummary: String {
        var providers: [String] = []
        if subscription.isConnected { providers.append("Codex") }
        for kind in [InstalledAIKind.claude, .openCode, .copilot]
        where installedAI.status(for: kind).isReady {
            providers.append(kind.title)
        }
        let enabledConnections = settings.connections.count {
            settings.isRouteEnabled(.api($0.id))
        }
        if enabledConnections > 0 {
            providers.append(
                enabledConnections == 1 ? "1 API connection" : "\(enabledConnections) API connections")
        }
        return providers.isEmpty ? "No external providers ready" : providers.joined(separator: ", ")
    }

    private var chatSection: some View {
        @Bindable var settings = settings
        @Bindable var appSettings = appSettings
        return Section {
            SettingsRow(
                title: "Floating bar",
                subtitle: "A shortcut that summons AI Chat as a bar you can place anywhere — it "
                    + "shares this chat and history.",
                subtitleLineLimit: 2, anchor: .aiChat
            ) {
                ShortcutRecorder(action: .toggleAIBar)
            }
            Toggle(isOn: $appSettings.aiBarStaysOpen) {
                SettingsRowTitle(.aiChat, "Keep the floating bar open")
                Text("Stay open when you click into another app, instead of closing on focus loss.")
            }
            Toggle(isOn: $settings.webSearchEnabled) {
                SettingsRowTitle(.aiChat, "Web search")
                Text(
                    "Sends prompts on to a search engine when the route offers one — Codex and OpenRouter.")
            }
            Picker(selection: $settings.toolRounds) {
                ForEach(AIToolRounds.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.aiChat, "Tool call rounds")
                Text(
                    "A reply stops after this many; Unlimited runs until Stop. API connections only.")
            }
            Toggle(isOn: $settings.showReasoning) {
                SettingsRowTitle(.aiChat, "Stream reasoning")
                Text("Opens the model's thinking as it streams; each stretch folds once it ends.")
            }
            Toggle(isOn: $settings.computerUseEnabled) {
                SettingsRowTitle(.aiChat, "Computer use")
                Text(
                    "Lets a vision-capable model see the screen and drive the mouse and keyboard, "
                        + "acting on its own within a reply. Needs Screen Recording and Accessibility.")
            }
            Toggle(isOn: $settings.browserRelayEnabled) {
                SettingsRowTitle(.aiChat, "Browser relay")
                Text(
                    "Lets the chat list, open, read and run JavaScript in tabs of your own Chrome, "
                        + "logins included, through omp's browser relay (omp browser-relay and its "
                        + "Chrome extension).")
            }
            Toggle(isOn: $settings.shellAccessEnabled) {
                SettingsRowTitle(.aiChat, "Shell access")
                Text(
                    "Lets the chat run shell and AppleScript commands to act on your Mac directly, "
                        + "without a permission prompt — on the Claude and Copilot routes only. Off "
                        + "by default; it can run anything you can.")
            }
        } header: {
            SettingsSectionHeader(.aiChat)
        } footer: {
            Text("Images pasted into the chat go to any model that accepts them; others never see one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var conversationsSection: some View {
        @Bindable var settings = settings
        return Section {
            Picker(selection: $settings.opensTo) {
                ForEach(AIOpensTo.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.aiConversations, "Opens to")
                Text("What summoning AI Chat lands on.")
            }
            if settings.opensTo == .recent {
                Picker(selection: $settings.newChatAfter) {
                    ForEach(AINewChatAfter.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsRowTitle(.aiConversations, "Start a new conversation after")
                    Text("Idle this long and the next summon starts fresh instead.")
                }
            }
            Picker(selection: $settings.retention) {
                ForEach(AIRetention.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.aiConversations, "Keep conversations")
                Text("Older conversations are deleted permanently.")
            }
        } header: {
            SettingsSectionHeader(.aiConversations)
        } footer: {
            Text(
                "Conversations stay on this Mac. Nothing here is carried in a settings backup — which "
                    + "chats a Mac keeps is that Mac's business."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var systemPromptSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.systemPromptEnabled) {
                SettingsRowTitle(.aiSystemPrompt, "Send a system prompt")
                Text("Off sends nothing ahead of your message, not even what Onecast says about itself.")
            }
            SystemPromptEditor(text: $settings.systemPrompt)
                .settingsEnabled(settings.systemPromptEnabled)
        } header: {
            SettingsSectionHeader(.aiSystemPrompt)
        } footer: {
            Text(
                "Your text is sent ahead of every message in every chat, after what Onecast "
                    + "already tells the model about itself. Both are billed again on each turn."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func syncSelection() {
        settings.reconcile(subscription: subscription, installedAI: installedAI)
    }
}
