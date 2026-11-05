import SwiftUI

struct NotchRootView: View {
    let viewModel: NotchViewModel

    var body: some View {
        NotchContainer(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct NotchContainer: View {
    let viewModel: NotchViewModel

    var body: some View {
        let shape = NotchShape(topRadius: viewModel.topRadius, bottomRadius: viewModel.bottomRadius)
        let size = viewModel.shapeSize

        ZStack(alignment: .top) {
            shape.fill(.black)
            content
                .padding(.horizontal, viewModel.topRadius)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay {
            // Light hover hint: hairline border + soft glow (not while expanded).
            shape
                .stroke(.white.opacity(showsHoverHint ? 0.28 : 0), lineWidth: 1)
                .shadow(color: .white.opacity(showsHoverHint ? 0.35 : 0), radius: 6)
        }
        .contentShape(shape)
        .onTapGesture { viewModel.tapNotch() }

        .shadow(color: .black.opacity(viewModel.mode == .collapsed ? 0 : 0.45), radius: 14, y: 6)
        .environment(\.colorScheme, .dark)
    }

    private var showsHoverHint: Bool {
        viewModel.isHovering && viewModel.mode != .expanded
    }

    @ViewBuilder private var content: some View {
        switch viewModel.mode {
        case .collapsed:
            WingsRow(viewModel: viewModel)
        case .peek:
            VStack(spacing: 0) {
                WingsRow(viewModel: viewModel)
                if let peek = viewModel.peek {
                    PeekView(peek: peek, viewModel: viewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                }
            }
        case .expanded:
            ExpandedView(viewModel: viewModel)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }
}

/// The row at notch height: live info left and right of the hardware notch.
private struct WingsRow: View {
    let viewModel: NotchViewModel

    var body: some View {
        HStack(spacing: 0) {
            wing { leading }
            Spacer(minLength: viewModel.notchSize.width)
            wing { trailing }
        }
        .frame(height: viewModel.notchSize.height)
    }

    private func wing(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(width: viewModel.hasWings ? viewModel.wingWidth : 0)
            .clipped()
    }

    @ViewBuilder private var leading: some View {
        switch viewModel.liveActivity {
        case .meeting(let countdown):
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(countdown.color)
        case .music(let music):
            ArtworkView(url: music.artworkURL, size: 16, cornerRadius: 4)
        case .demo:
            RoundedRectangle(cornerRadius: 5)
                .fill(LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 20, height: 20)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch viewModel.liveActivity {
        case .meeting(let countdown):
            if viewModel.countdownStopArmed {
                // Red ring + red square with black (background) space in between.
                ZStack {
                    Circle()
                        .strokeBorder(.red, lineWidth: 1.5)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.red)
                        .frame(width: 7, height: 7)
                }
                .frame(width: 18, height: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.stopCountdown() }
                    .help("Hide this countdown")
                    .transition(.scale.combined(with: .opacity))
            } else {
                CountdownText(start: countdown.start)
                    .transition(.scale.combined(with: .opacity))
            }
        case .music:
            EqualizerBars()
        case .demo:
            Text("09:41")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.orange)
        case nil:
            EmptyView()
        }
    }
}

/// mm:ss until `start`, "now" once it has started.
struct CountdownText: View {
    let start: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = Int(start.timeIntervalSince(context.date).rounded(.up))
            Group {
                if remaining > 0 {
                    Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .foregroundStyle(remaining <= 60 ? .red : .orange)
                } else {
                    Text("now").foregroundStyle(.green)
                }
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
        }
    }
}

private struct PeekView: View {
    let peek: NotchViewModel.Peek
    let viewModel: NotchViewModel

    var body: some View {
        HStack(spacing: 10) {
            if let artworkURL = peek.artworkURL {
                ArtworkView(url: artworkURL, size: 34, cornerRadius: 6)
            } else {
                Image(systemName: peek.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(peek.tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(peek.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let subtitle = peek.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let action = peek.action {
                Button {
                    action.perform()
                    viewModel.dismissPeek()
                } label: {
                    Label(action.title, systemImage: action.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.green.opacity(0.85)))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(maxHeight: .infinity)
    }
}
