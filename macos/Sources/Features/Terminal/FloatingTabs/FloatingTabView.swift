import SwiftUI

struct FloatingTabView: View {
    @ObservedObject var model: FloatingTabModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoverTask: Task<Void, Never>?
    @State private var isDragging = false
    var headerOffset: CGFloat = 0
    var onDrag: (CGSize) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Button {
                hoverTask?.cancel()
                model.isExpanded.toggle()
            } label: {
                HStack(spacing: FloatingTabStyle.itemSpacing) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: FloatingTabStyle.iconWidth)
                    Text(model.selectedTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: model.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, FloatingTabStyle.horizontalPadding)
                .frame(height: FloatingTabStyle.rowHeight)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Tabs")
            .accessibilityValue(model.selectedTitle)
            .accessibilityIdentifier("FloatingTabsToggle")
            .help(model.selectedTitle)
            .highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        hoverTask?.cancel()
                        isDragging = true
                        onDrag(value.translation)
                    }
                    .onEnded { _ in
                        onDragEnded()
                        isDragging = false
                    }
            )
            .offset(y: headerOffset)

            if model.isExpanded {
                expandedContent
                    .offset(y: headerOffset > 0 ? -FloatingTabStyle.rowHeight : 0)
            }
        }
        .font(.system(size: 12))
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: FloatingTabStyle.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: FloatingTabStyle.cornerRadius)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: FloatingTabStyle.cornerRadius))
        .animation(reduceMotion || isDragging ? nil : .easeOut(duration: 0.12), value: model.isExpanded)
        .onHover { hovering in
            hoverTask?.cancel()
            guard !isDragging, !model.isKeyboardNavigating else { return }
            if hovering {
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: FloatingTabStyle.hoverDelay)
                    guard !Task.isCancelled else { return }
                    model.isExpanded = true
                }
            } else {
                model.isExpanded = false
            }
        }
        .onChange(of: model.isKeyboardNavigating) { navigating in
            if navigating { hoverTask?.cancel() }
        }
        .onDisappear {
            hoverTask?.cancel()
            isDragging = false
            onDragEnded()
            model.isExpanded = false
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.items) { item in
                            FloatingTabRow(item: item, keyboardSelected: model.keyboardSelection == .tab(item.id)) {
                                model.select(item)
                            } close: {
                                model.close(item)
                            }
                            .id(item.id)
                        }
                    }
                }
                .onAppear {
                    if case let .tab(identifier)? = model.keyboardSelection { proxy.scrollTo(identifier) }
                }
                .onChange(of: model.keyboardSelection) { selection in
                    if case let .tab(identifier)? = selection { proxy.scrollTo(identifier) }
                }
            }
            .accessibilityIdentifier("FloatingTabsList")
            Divider()
            Button(action: model.newTab) {
                HStack(spacing: FloatingTabStyle.itemSpacing) {
                    Image(systemName: "plus")
                        .frame(width: FloatingTabStyle.iconWidth)
                    Text("New Tab")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, FloatingTabStyle.horizontalPadding)
                .frame(height: FloatingTabStyle.rowHeight)
                .background(model.keyboardSelection == .newTab ? Color.accentColor.opacity(0.2) : .clear)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("FloatingTabsNewTab")
            .accessibilityValue(model.keyboardSelection == .newTab ? "Keyboard focused" : "")
        }
    }
}

private struct FloatingTabRow: View {
    let item: FloatingTabItem
    let keyboardSelected: Bool
    let action: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: FloatingTabStyle.itemSpacing) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .opacity(item.selected ? 1 : 0)
                        .frame(width: FloatingTabStyle.iconWidth)
                    Text(item.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, FloatingTabStyle.horizontalPadding)
                .padding(.trailing, FloatingTabStyle.itemSpacing)
                .frame(height: FloatingTabStyle.rowHeight)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(item.title)
            .accessibilityValue(keyboardSelected ? "Keyboard focused" : "")
            .accessibilityAddTraits(item.selected ? [.isSelected] : [])
            .accessibilityIdentifier("FloatingTabRow")
            .help(item.title)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: FloatingTabStyle.closeButtonWidth, height: FloatingTabStyle.closeButtonWidth)
                    .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
            }
            .padding(.trailing, FloatingTabStyle.horizontalPadding)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .accessibilityHidden(!hovering)
            .accessibilityLabel("Close \(item.title)")
            .accessibilityIdentifier("FloatingTabClose")
            .help("Close tab")
        }
        .frame(height: FloatingTabStyle.rowHeight)
        .background(
            keyboardSelected ? Color.accentColor.opacity(0.2) :
                hovering ? Color.primary.opacity(0.08) : .clear
        )
        .onHover { hovering = $0 }
    }
}
