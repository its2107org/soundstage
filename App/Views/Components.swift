import SwiftUI

// MARK: - Look

extension SoundMode {
    var colour: Color {
        switch self {
        case .movie: Color(red: 1.0, green: 0.6, blue: 0.24)
        case .music: Color(red: 0.62, green: 0.42, blue: 1.0)
        case .game: Color(red: 0.24, green: 0.8, blue: 0.48)
        case .standard: Color(red: 0.32, green: 0.58, blue: 1.0)
        case .direct: Color(red: 0.16, green: 0.76, blue: 0.78)
        case .party: Color(red: 1.0, green: 0.34, blue: 0.58)
        }
    }
}

struct Card<Content: View>: View {
    var title: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || trailing != nil {
                HStack {
                    if let title {
                        Text(title)
                            .font(.headline)
                    }
                    Spacer()
                    trailing
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct AmbientBackground: View {
    var colour: Color?

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
            if let colour {
                LinearGradient(colors: [colour.opacity(0.32), colour.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 440)
                    .blur(radius: 60)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.6), value: colour)
    }
}

/// A rounded pill used for presets, inputs and equaliser picks.
struct Chip: View {
    var title: String
    var symbol: String?
    var selected: Bool
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 7) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 15)
        .frame(height: 40)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? AnyShapeStyle(tint) : AnyShapeStyle(Color(.tertiarySystemFill)), in: Capsule())
        .contentShape(Capsule())
    }
}

/// Small round icon button (volume steps, etc.).
struct RoundIconButton: View {
    var symbol: String
    var size: CGFloat = 46
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .frame(width: size, height: size)
                .background(Color(.tertiarySystemFill), in: Circle())
                .foregroundStyle(.primary)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }
}

func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
func signed(_ value: Double) -> String { signed(Int(value.rounded())) }

// MARK: - Volume slider

/// A wide, chunky slider like the one in Control Centre. Dragging moves the volume relative to
/// where it was (a stray tap never jumps it to full blast).
struct VolumeSlider: View {
    var value: Int
    var muted: Bool
    var tint: Color
    var onChange: (Int) -> Void

    @State private var dragStart: Int?

    var body: some View {
        GeometryReader { geo in
            let fraction = CGFloat(value) / 100
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(muted ? AnyShapeStyle(Color.secondary.opacity(0.5)) : AnyShapeStyle(tint.gradient))
                    .frame(width: max(geo.size.height, geo.size.width * fraction))
                    .opacity(value == 0 ? 0.35 : 1)
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(value > 6 ? Color.white : Color.secondary)
                    Spacer()
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(value > 92 ? Color.white : Color.secondary)
                }
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 18)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { drag in
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = value }
                        let delta = Int((drag.translation.width / max(1, geo.size.width) * 100).rounded())
                        let next = min(100, max(0, start + delta))
                        if next != value { onChange(next) }
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.9), value: value)
        }
        .frame(height: 58)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(100, value + 2))
            case .decrement: onChange(max(0, value - 2))
            @unknown default: break
            }
        }
    }
}

// MARK: - Equaliser slider

/// One tall equaliser band. Fills from the 0 dB line towards the value.
struct BandSlider: View {
    var title: String
    var value: Double
    var range: ClosedRange<Double>
    var tint: Color
    var onChange: (Double) -> Void

    @State private var dragStart: Double?

    var body: some View {
        VStack(spacing: 10) {
            Text(signed(value))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: value))
            GeometryReader { geo in
                let span = range.upperBound - range.lowerBound
                let height = geo.size.height
                let zeroY = height * CGFloat((range.upperBound - 0) / span)
                let valueY = height * CGFloat((range.upperBound - value) / span)
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                    Rectangle()
                        .fill(tint.gradient)
                        .frame(height: max(4, abs(zeroY - valueY)))
                        .offset(y: min(zeroY, valueY) - (value == 0 ? 2 : 0))
                    Rectangle()
                        .fill(Color.primary.opacity(0.25))
                        .frame(height: 1.5)
                        .offset(y: zeroY)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { drag in
                            let start = dragStart ?? value
                            if dragStart == nil { dragStart = value }
                            let delta = -Double(drag.translation.height / max(1, height)) * span
                            let next = min(range.upperBound, max(range.lowerBound, (start + delta).rounded()))
                            if next != value { onChange(next) }
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.9), value: value)
            }
            .frame(width: 64, height: 180)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue("\(signed(value)) decibels")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(range.upperBound, value + 1))
            case .decrement: onChange(max(range.lowerBound, value - 1))
            @unknown default: break
            }
        }
    }
}
