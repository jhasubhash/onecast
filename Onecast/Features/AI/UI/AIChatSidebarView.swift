import SwiftUI

/// The AI Chat window's conversations: this scope's saved chats, pinned first then by day.
struct AIChatSidebarView: View {
    let session: AIChatWindowSession

    @Environment(\.metrics) private var metrics
    @State private var query = ""
    @State private var renaming: UUID?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    private struct Group: Identifiable {
        let title: String
        var conversations: [ChatConversation]
        var id: String { title }
    }

    private var coordinator: AIChatCoordinator { session.coordinator }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, metrics.spacing.lg)
                .padding(.vertical, metrics.spacing.md)
            List(selection: selection) {
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.conversations) { conversation in
                            row(conversation)
                                .tag(conversation.id)
                                .contextMenu { menu(for: conversation.id) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onDeleteCommand {
                guard let id = selection.wrappedValue else { return }
                delete(id)
            }
            .overlay { emptyState }
        }
    }

    /// Selecting a row opens it in the window; the window's own chat is the selection.
    private var selection: Binding<UUID?> {
        Binding(
            get: { session.chat.session.id },
            set: { id in if let id { session.open(id: id) } })
    }

    /// Recency order already puts each day's chats together, so a day opens exactly once.
    private var groups: [Group] {
        let results = session.history.search(query)
        var groups: [Group] = []
        let pinned = results.filter(\.isPinned)
        if !pinned.isEmpty { groups.append(Group(title: "Pinned", conversations: pinned)) }
        for conversation in results where !conversation.isPinned {
            let title = DateBucket(for: conversation.updatedAt).title
            if groups.last?.title == title {
                groups[groups.count - 1].conversations.append(conversation)
            } else {
                groups.append(Group(title: title, conversations: [conversation]))
            }
        }
        return groups
    }

    @ViewBuilder private var emptyState: some View {
        if !session.history.isAvailable {
            ContentUnavailableView("History Unavailable", systemImage: "exclamationmark.triangle")
        } else if groups.isEmpty, !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if groups.isEmpty {
            ContentUnavailableView("No Chats Yet", systemImage: "bubble.left.and.bubble.right")
        }
    }

    private var searchField: some View {
        HStack(spacing: metrics.spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Colors.textTertiary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(Capsule().fill(Theme.Colors.controlSurface))
        .onExitCommand { query = "" }
    }

    @ViewBuilder
    private func row(_ conversation: ChatConversation) -> some View {
        if renaming == conversation.id {
            TextField("Chat name", text: $renameText, prompt: Text(conversation.title))
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit { commitRename(conversation.id) }
                .onExitCommand { renaming = nil }
                .onChange(of: renameFocused) { _, focused in
                    if !focused { commitRename(conversation.id) }
                }
        } else {
            HStack(spacing: metrics.spacing.sm) {
                Text(conversation.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if session.answeringIDs.contains(conversation.id) {
                    ProgressView().controlSize(.mini)
                } else if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .font(metrics.typography.keyCap)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for id: UUID) -> some View {
        let pinned = coordinator.isPinned(id: id)
        Button(pinned ? "Unpin Chat" : "Pin Chat") { coordinator.togglePin(id: id) }
        Button("Rename…") { beginRename(id) }
        Divider()
        Button("Copy Chat") { coordinator.copyChat(id: id) }
        Button("Export as Markdown…") { coordinator.exportChat(id: id) }
        Divider()
        Button("Delete Chat…", role: .destructive) { delete(id) }
    }

    private func beginRename(_ id: UUID) {
        renameText = session.history.conversation(id: id)?.customTitle ?? ""
        renaming = id
        renameFocused = true
    }

    private func commitRename(_ id: UUID) {
        guard renaming == id else { return }
        coordinator.rename(id: id, to: renameText)
        renaming = nil
    }

    private func delete(_ id: UUID) {
        Task { @MainActor in
            guard await coordinator.confirmDelete(id: id) else { return }
            session.delete(id: id)
        }
    }
}
