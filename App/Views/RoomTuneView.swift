import AVKit
import Combine
import SwiftUI

/// "Tune to room": plays a test sound through the soundbar and sets the equaliser and subwoofer.
struct RoomTuneView: View {
    @State private var tuner = RoomTuner()
    @State private var model = SoundbarModel.shared
    @State private var wireless = RoomTuning.outputIsWireless
    @State private var outputName = RoomTuning.outputName
    @Environment(\.dismiss) private var dismiss

    private let routeChanged = NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    switch tuner.phase {
                    case .ready: intro
                    case .listeningToRoom: running(progress: 0, text: "Listening to the room…")
                    case .playing(let progress): running(progress: progress, text: "Playing the test sound…")
                    case .done(let result): done(result)
                    case .failed(let message): failed(message)
                    }
                }
                .padding(20)
                .animation(.smooth, value: tuner.phase)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Tune to room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tuner.isRunning ? "Stop" : "Close") {
                        if tuner.isRunning { tuner.cancel() }
                        dismiss()
                    }
                }
            }
            .onReceive(routeChanged) { _ in
                DispatchQueue.main.async {
                    wireless = RoomTuning.outputIsWireless
                    outputName = RoomTuning.outputName
                }
            }
        }
        .interactiveDismissDisabled(tuner.isRunning)
    }

    // MARK: Steps

    private var intro: some View {
        VStack(spacing: 22) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 50, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 14) {
                step(1, "Sit where you usually sit, and hold your phone at head height, pointing at the TV.")
                step(2, "Send your phone's sound to the soundbar.")
                step(3, "Tap Start. You'll hear a hiss for about 15 seconds.")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: wireless ? "checkmark.circle.fill" : "airplayaudio")
                        .font(.title3)
                        .foregroundStyle(wireless ? Color.green : Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wireless ? "Sound is going to \(outputName ?? "a speaker")" : "Sound is playing on this phone")
                            .font(.subheadline.weight(.semibold))
                        Text(wireless ? "Make sure that's your soundbar." : "Tap the button and choose your soundbar.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    RoutePicker()
                        .frame(width: 44, height: 44)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Button { tuner.start() } label: {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(!wireless)

            Text("Sets bass, mid, treble and the subwoofer level. Your sound mode and input are put back afterwards.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.18), in: Circle())
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func running(progress: Double, text: String) -> some View {
        VStack(spacing: 26) {
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: progress)
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }
            .frame(width: 170, height: 170)
            .padding(.top, 40)
            Text(text)
                .font(.title3.weight(.semibold))
            Text("Keep still and quiet.")
                .foregroundStyle(.secondary)
        }
    }

    private func done(_ result: RoomTuning.Result) -> some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
                .padding(.top, 10)
            Text("Tuned to your room")
                .font(.title2.weight(.bold))

            VStack(spacing: 0) {
                resultRow("Bass", signed(result.bass))
                Divider()
                resultRow("Mid", signed(result.mid))
                Divider()
                resultRow("Treble", signed(result.treble))
                if model.state.levels["sub"] != nil {
                    Divider()
                    resultRow("Subwoofer", signed(result.sub))
                }
            }
            .padding(.horizontal, 18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            ResponseChart(response: result.response)
                .frame(height: 150)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    tuner.restore()
                    dismiss()
                } label: {
                    Text("Undo").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                Button {
                    tuner.keep()
                    dismiss()
                } label: {
                    Text("Keep").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            Text("Switch your phone's sound back to the phone in Control Centre when you're done.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func resultRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 13)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
                .padding(.top, 30)
            Text(message)
                .multilineTextAlignment(.center)
            Button { tuner.start() } label: {
                Text("Try again").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }
}

/// How loud each octave arrived at the seat before tuning (0 = even).
private struct ResponseChart: View {
    let response: [Double]
    private let labels = ["32", "63", "125", "250", "500", "1k", "2k", "4k", "8k"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What your room did to the sound")
                .font(.subheadline.weight(.semibold))
            GeometryReader { geo in
                let count = max(response.count, 1)
                let width = geo.size.width / CGFloat(count)
                let mid = geo.size.height / 2
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.2))
                        .frame(height: 1)
                        .offset(y: mid)
                    ForEach(Array(response.enumerated()), id: \.offset) { index, value in
                        let clamped = min(12, max(-12, value))
                        let height = abs(CGFloat(clamped) / 12) * (mid - 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(clamped >= 0 ? Color.accentColor : Color.accentColor.opacity(0.5))
                            .frame(width: width * 0.6, height: max(2, height))
                            .offset(x: CGFloat(index) * width + width * 0.2, y: clamped >= 0 ? mid - height : mid)
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// The system "choose where sound plays" button.
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.activeTintColor = .tintColor
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
