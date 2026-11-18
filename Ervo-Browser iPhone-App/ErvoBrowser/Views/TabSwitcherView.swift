import SwiftUI

/// Grid of open tabs (normal / private), like Chrome's tab switcher.
struct TabSwitcherView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showPrivate = false

    private var list: [TabModel] { showPrivate ? store.privateTabs : store.tabs }

    var body: some View {
        NavigationStack {
            ScrollView {
                if list.isEmpty {
                    ContentUnavailableView(
                        showPrivate ? L.t("privateTitle") : L.t("newTab"),
                        systemImage: showPrivate ? "eyeglasses" : "square.on.square"
                    )
                    .padding(.top, 80)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 14)], spacing: 16) {
                        ForEach(list) { tab in
                            TabCard(tab: tab, isActive: tab.id == store.activeTab?.id) {
                                store.select(tab)
                                dismiss()
                            } onClose: {
                                withAnimation(.snappy) { store.closeTab(tab) }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $showPrivate) {
                        Text(L.t("tabs")).tag(false)
                        Text(L.t("privateTab")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("done")) { dismiss() }
                        .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(L.t("closeAll"), role: .destructive) {
                        withAnimation { store.closeAll(isPrivate: showPrivate) }
                    }
                    .disabled(list.isEmpty)
                    Spacer()
                    Button {
                        store.openTab(isPrivate: showPrivate)
                        store.requestAddressBarFocus()
                        dismiss()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel(showPrivate ? L.t("newPrivateTab") : L.t("newTab"))
                    Spacer()
                    Button(L.t("done")) { dismiss() }
                }
            }
            .onAppear { showPrivate = store.isPrivateMode }
        }
    }
}

struct TabCard: View {
    let tab: TabModel
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                FaviconView(url: tab.url, size: 14)
                Text(tab.displayTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("closeTab"))
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .frame(height: 32)
            .background(isActive ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            .foregroundStyle(isActive ? Color.white : Color.primary)

            ZStack {
                Color(.systemBackground)
                if let snapshot = tab.snapshot, !tab.isBlank {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .opacity(0.8)
                }
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isActive ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color(.separator)), lineWidth: isActive ? 2.5 : 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: onSelect)
        .offset(x: dragOffset)
        .opacity(1 - min(0.7, abs(dragOffset) / 300))
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    if abs(value.translation.width) > 110 && abs(value.translation.width) > abs(value.translation.height) {
                        withAnimation(.easeOut(duration: 0.2)) { dragOffset = value.translation.width > 0 ? 500 : -500 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onClose() }
                    } else {
                        withAnimation(.spring(duration: 0.3)) { dragOffset = 0 }
                    }
                }
        )
        .accessibilityAddTraits(.isButton)
    }
}
