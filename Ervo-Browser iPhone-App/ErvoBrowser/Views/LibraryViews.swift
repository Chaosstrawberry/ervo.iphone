import SwiftUI
import QuickLook
import UniformTypeIdentifiers

// MARK: - Bookmarks

struct BookmarksView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var renaming: Bookmark?
    @State private var newTitle = ""
    @State private var importing = false
    @State private var exportURL: URL?

    private var filtered: [Bookmark] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.bookmarks }
        return store.bookmarks.filter { "\($0.title) \($0.url.absoluteString)".lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { bookmark in
                    Button {
                        store.open(bookmark.url)
                        dismiss()
                    } label: {
                        LinkRow(title: bookmark.title, url: bookmark.url)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            store.deleteBookmark(bookmark)
                        } label: {
                            Label(L.t("delete"), systemImage: "trash")
                        }
                        Button {
                            newTitle = bookmark.title
                            renaming = bookmark
                        } label: {
                            Label(L.t("rename"), systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                    .contextMenu {
                        Button {
                            store.open(bookmark.url, newTab: true)
                            dismiss()
                        } label: {
                            Label(L.t("openInNewTab"), systemImage: "plus.square.on.square")
                        }
                        Button {
                            UIPasteboard.general.url = bookmark.url
                        } label: {
                            Label(L.t("copyLink"), systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            store.deleteBookmark(bookmark)
                        } label: {
                            Label(L.t("delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if store.bookmarks.isEmpty {
                    ContentUnavailableView(L.t("noBookmarks"), systemImage: "star", description: Text(L.t("noBookmarksHint")))
                }
            }
            .searchable(text: $query)
            .navigationTitle(L.t("bookmarks"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            importing = true
                        } label: {
                            Label(L.t("importBookmarks"), systemImage: "square.and.arrow.down")
                        }
                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Label(L.t("exportBookmarks"), systemImage: "square.and.arrow.up")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(L.t("menu"))
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.html]) { result in
                if case let .success(url) = result {
                    let count = store.importBookmarks(from: url)
                    store.showToast(count > 0 ? L.f("imported", String(count)) : L.t("noneImported"))
                    exportURL = store.exportBookmarksFile()
                }
            }
            .onAppear { exportURL = store.exportBookmarksFile() }
            .onChange(of: store.bookmarks.count) { exportURL = store.exportBookmarksFile() }
            .alert(L.t("rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(L.t("name"), text: $newTitle)
                Button(L.t("cancel"), role: .cancel) { renaming = nil }
                Button(L.t("save")) {
                    if let bookmark = renaming { store.renameBookmark(bookmark, to: newTitle) }
                    renaming = nil
                }
            }
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var confirmClear = false

    private struct DayGroup: Identifiable {
        let day: Date
        let entries: [HistoryEntry]
        var id: Date { day }
    }

    private var groups: [DayGroup] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let entries = q.isEmpty ? store.history : store.history.filter { "\($0.title) \($0.url.absoluteString)".lowercased().contains(q) }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries.prefix(1000)) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { DayGroup(day: $0, entries: grouped[$0] ?? []) }
    }

    private func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return L.t("today") }
        if calendar.isDateInYesterday(day) { return L.t("yesterday") }
        return day.formatted(date: .complete, time: .omitted)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    Section(title(for: group.day)) {
                        ForEach(group.entries) { entry in
                            Button {
                                store.open(entry.url)
                                dismiss()
                            } label: {
                                HStack {
                                    LinkRow(title: entry.title, url: entry.url)
                                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.deleteHistory(entry)
                                } label: {
                                    Label(L.t("delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if store.history.isEmpty {
                    ContentUnavailableView(L.t("noHistory"), systemImage: "clock")
                }
            }
            .searchable(text: $query)
            .navigationTitle(L.t("history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("clearHistory"), role: .destructive) { confirmClear = true }
                        .disabled(store.history.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("done")) { dismiss() }
                }
            }
            .confirmationDialog(L.t("clearHistory"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button(L.t("clearHistory"), role: .destructive) { store.clearHistory() }
                Button(L.t("cancel"), role: .cancel) {}
            }
        }
    }
}

// MARK: - Downloads

struct DownloadsView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var preview: URL?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.downloads, id: \.self) { file in
                    Button {
                        preview = file
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc")
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 28)
                            Text(file.lastPathComponent)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            ShareLink(item: file) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            store.deleteDownload(file)
                        } label: {
                            Label(L.t("delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if store.downloads.isEmpty {
                    ContentUnavailableView(L.t("noDownloads"), systemImage: "arrow.down.circle")
                }
            }
            .quickLookPreview($preview)
            .navigationTitle(L.t("downloads"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("done")) { dismiss() }
                }
            }
            .onAppear { store.refreshDownloads() }
        }
    }
}

// MARK: - Shared row

struct LinkRow: View {
    let title: String
    let url: URL

    var body: some View {
        HStack(spacing: 12) {
            FaviconView(url: url, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? (url.host() ?? url.absoluteString) : title)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(URLResolver.displayHost(url))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
