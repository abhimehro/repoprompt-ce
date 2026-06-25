//  NotificationsButtonView.swift
//  RepoPrompt
//
//  Created by RepoPrompt Code Assistant on 2025-07-07.

import AppKit
import SwiftUI

/// A single bell-shaped toolbar item that aggregates dismissible docs/tutorial notifications.
@MainActor
struct NotificationsButtonView: View {
    // MARK: – Dependencies

    /// TOOLBAR POPOVER FIX: Accept binding from parent to survive toolbar re-evaluation
    @Binding var showPopover: Bool

    // Persisted dismissal flags for Docs and Tutorial.
    @AppStorage("DocsButtonDismissed") private var docsDismissed: Bool = false
    @AppStorage("TutorialButtonDismissed") private var tutorialDismissed: Bool = false

    // Muted notification flags - these can be un-muted later
    @AppStorage("DocsButtonMuted") private var docsMuted: Bool = false
    @AppStorage("TutorialButtonMuted") private var tutorialMuted: Bool = false

    // Latest video notification (Repo Prompt 101 playlist)
    @AppStorage("RepoPrompt101ButtonDismissed") private var repoPrompt101Dismissed: Bool = false
    @AppStorage("RepoPrompt101ButtonMuted") private var repoPrompt101Muted: Bool = false

    init(showPopover: Binding<Bool>) {
        _showPopover = showPopover
    }

    // MARK: – Derived data

    struct NotificationItem: Identifiable {
        enum Kind { case docs, tutorial, repoPrompt101 }

        let id = UUID()
        let kind: Kind
        let iconName: String
        let title: String
        let actionTitle: String
        let primary: () -> Void
        let dismiss: () -> Void
        let mute: (() -> Void)?
        let unmute: (() -> Void)?
        let isMuted: Bool
    }

    private var pendingItems: [NotificationItem] {
        var arr: [NotificationItem] = []

        if !docsDismissed, !docsMuted {
            arr.append(
                NotificationItem(
                    kind: .docs,
                    iconName: "doc.text",
                    title: "Read the Docs",
                    actionTitle: "Open Docs",
                    primary: openDocs,
                    dismiss: { docsDismissed = true },
                    mute: { docsMuted = true },
                    unmute: nil,
                    isMuted: false
                )
            )
        }

        if !tutorialDismissed, !tutorialMuted {
            arr.append(
                NotificationItem(
                    kind: .tutorial,
                    iconName: "questionmark.circle",
                    title: "Watch Tutorial",
                    actionTitle: "Play Video",
                    primary: openTutorial,
                    dismiss: { tutorialDismissed = true },
                    mute: { tutorialMuted = true },
                    unmute: nil,
                    isMuted: false
                )
            )
        }

        if !repoPrompt101Dismissed, !repoPrompt101Muted {
            arr.append(
                NotificationItem(
                    kind: .repoPrompt101,
                    iconName: "play.rectangle.on.rectangle",
                    title: "Repo Prompt 101",
                    actionTitle: "Watch Playlist",
                    primary: openRepoPrompt101,
                    dismiss: { repoPrompt101Dismissed = true },
                    mute: { repoPrompt101Muted = true },
                    unmute: nil,
                    isMuted: false
                )
            )
        }

        return arr
    }

    private var mutedItems: [NotificationItem] {
        var arr: [NotificationItem] = []

        if !docsDismissed, docsMuted {
            arr.append(
                NotificationItem(
                    kind: .docs,
                    iconName: "doc.text",
                    title: "Read the Docs",
                    actionTitle: "Open Docs",
                    primary: openDocs,
                    dismiss: { docsDismissed = true },
                    mute: nil,
                    unmute: { docsMuted = false },
                    isMuted: true
                )
            )
        }

        if !tutorialDismissed, tutorialMuted {
            arr.append(
                NotificationItem(
                    kind: .tutorial,
                    iconName: "questionmark.circle",
                    title: "Watch Tutorial",
                    actionTitle: "Play Video",
                    primary: openTutorial,
                    dismiss: { tutorialDismissed = true },
                    mute: nil,
                    unmute: { tutorialMuted = false },
                    isMuted: true
                )
            )
        }

        if !repoPrompt101Dismissed, repoPrompt101Muted {
            arr.append(
                NotificationItem(
                    kind: .repoPrompt101,
                    iconName: "play.rectangle.on.rectangle",
                    title: "Repo Prompt 101",
                    actionTitle: "Watch Playlist",
                    primary: openRepoPrompt101,
                    dismiss: { repoPrompt101Dismissed = true },
                    mute: nil,
                    unmute: { repoPrompt101Muted = false },
                    isMuted: true
                )
            )
        }

        return arr
    }

    private var badge: some View {
        Text("\(pendingItems.count)")
            .font(.caption2.weight(.bold))
            .foregroundColor(.white)
            .padding(4)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.8))
            )
            .offset(x: 10, y: -10)
            .opacity(pendingItems.count > 0 ? 1 : 0)
    }

    // MARK: – View body

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            Image(systemName: "bell")
                .imageScale(.medium)
                .foregroundColor(pendingItems.isEmpty ? .secondary : .primary)
                .overlay(badge, alignment: .topTrailing)
        }
        .accessibilityLabel(pendingItems.isEmpty ? "Notifications" : "Notifications, \(pendingItems.count) unread")
        .hoverTooltip("Notifications")
        .popover(isPresented: $showPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            NotificationsPopover(
                activeItems: pendingItems,
                mutedItems: mutedItems
            )
            .frame(width: 280)
        }
    }

    // MARK: – Helpers

    private func openDocs() {
        guard let url = URL(string: "https://repoprompt.com/docs#s=getting-started") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openTutorial() {
        guard let url = URL(string: "https://youtu.be/-J3CwrTrAlE?si=00Ig2DePtMyD_s03") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openRepoPrompt101() {
        guard let url = URL(string: "https://youtube.com/playlist?list=PLFg9suyZ1OnLh3Tv5bP6jvWXcKKTlI_4m&si=u6Rj9r3JQB_eEyaZ") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Popover content

private struct NotificationsPopover: View {
    let activeItems: [NotificationsButtonView.NotificationItem]
    let mutedItems: [NotificationsButtonView.NotificationItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if activeItems.isEmpty, mutedItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No new notifications")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text("You're all caught up!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                if !activeItems.isEmpty {
                    ForEach(activeItems) { item in
                        NotificationRow(item: item)
                        if item.id != activeItems.last?.id {
                            Divider()
                        }
                    }
                }

                if !mutedItems.isEmpty {
                    if !activeItems.isEmpty {
                        Divider()
                    }

                    Text("Muted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(mutedItems) { item in
                        NotificationRow(item: item)
                        if item.id != mutedItems.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Notification Row

private struct NotificationRow: View {
    let item: NotificationsButtonView.NotificationItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconName)
                .imageScale(.medium)
                .foregroundColor(item.isMuted ? .secondary : .primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundColor(item.isMuted ? .secondary : .primary)

                Button(item.actionTitle) {
                    item.primary()
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            Spacer()

            HStack(spacing: 4) {
                if item.isMuted {
                    Button(action: { item.unmute?() }) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Unmute \(item.title)")
                    .hoverTooltip("Unmute")
                } else if item.mute != nil {
                    Button(action: { item.mute?() }) {
                        Image(systemName: "speaker.slash")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mute \(item.title)")
                    .hoverTooltip("Mute")
                }

                Button(action: item.dismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .hoverTooltip("Dismiss")
            }
        }
        .opacity(item.isMuted ? 0.7 : 1.0)
    }
}
