import SwiftUI

/// Full panel. Top row sits beside the hardware notch; tabs and content below it.
struct ExpandedView: View {
    @Bindable var viewModel: NotchViewModel
    @Environment(NotionService.self) private var notion

    var body: some View {
        VStack(spacing: 0) {
            topRow
            tabBar
                .padding(.top, 6)
            Divider().overlay(.white.opacity(0.08))
                .padding(.horizontal, 14)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .onAppear(perform: fixSelection)
        .onChange(of: notion.widgets) { fixSelection() }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.selectedTab {
        case .calendar:
            CalendarTabView(notch: viewModel)
        case .notion(let id):
            if let widget = notion.widget(id) {
                NotionPageView(widget: widget, store: notion.store(for: widget), notch: viewModel)
                    .id(widget.id)
            }
        case .notionSetup:
            NotionSetupPrompt(notch: viewModel)
        case .spotify:
            NowPlayingView()
        }
    }

    private struct TabItem: Identifiable {
        let tab: NotchViewModel.Tab
        let title: String
        let icon: String?
        let emoji: String?
        var id: NotchViewModel.Tab { tab }
    }

    private var tabs: [TabItem] {
        var items = [TabItem(tab: .calendar, title: "Calendar", icon: "calendar", emoji: nil)]
        if notion.widgets.isEmpty {
            items.append(TabItem(tab: .notionSetup, title: "Notion", icon: "doc.text", emoji: nil))
        } else {
            items += notion.widgets.map {
                TabItem(tab: .notion($0.id), title: $0.displayName, icon: $0.icon == nil ? "doc.text" : nil, emoji: $0.icon)
            }
        }
        items.append(TabItem(tab: .spotify, title: "Spotify", icon: "music.note", emoji: nil))
        return items
    }

    /// Falls back to Calendar if the selected Notion widget was removed.
    private func fixSelection() {
        if !tabs.contains(where: { $0.tab == viewModel.selectedTab }) {
            viewModel.selectedTab = .calendar
        }
    }

    private var topRow: some View {
        HStack {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: viewModel.notchSize.width + 20)
            Button {
                viewModel.clickedOutside()
                viewModel.openSettings?()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            Button {
                viewModel.togglePinned()
            } label: {
                Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundStyle(viewModel.isPinned ? .orange : .secondary)
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(viewModel.isPinned ? "Unpin" : "Keep open")
        }
        .padding(.horizontal, 18)
        .frame(height: viewModel.notchSize.height)
    }

    private var tabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(tabs) { item in
                    let selected = viewModel.selectedTab == item.tab
                    Button {
                        viewModel.selectedTab = item.tab
                    } label: {
                        HStack(spacing: 5) {
                            if let emoji = item.emoji {
                                Text(emoji).font(.system(size: 11))
                            } else if let icon = item.icon {
                                Image(systemName: icon)
                            }
                            Text(item.title).lineLimit(1)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(selected ? 0.16 : 0)))
                        .foregroundStyle(selected ? .white : .secondary)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.never)
        .padding(.bottom, 8)
    }
}
