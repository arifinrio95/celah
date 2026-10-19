import SwiftUI

/// Lists saved meetings. Each row can open the folder in Finder or hand it to Claude or Codex.
struct MeetingsPanel: View {
    @EnvironmentObject var recorder: MeetingRecorder
    @State private var meetings: [(url: URL, size: String)] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SectionLabel(text: "Meetings", meta: "\(meetings.count) recordings")
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            Text("Claude opens a session with the folder and prompt filled in. Press Enter to start. Codex copies the prompt, so paste it.")
                .font(Theme.mono(9)).foregroundStyle(Theme.ink3).lineLimit(2)
                .padding(.horizontal, 16).padding(.bottom, 9)
            HLine()
            if loading {
                VStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.frame(maxWidth: .infinity)
            } else if meetings.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("No recordings yet").font(Theme.body(12)).foregroundStyle(Theme.ink3)
                    Text("Press Record on the board to start one").font(Theme.mono(9.5)).foregroundStyle(Theme.ink4)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(meetings, id: \.url) { row($0.url, $0.size) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .task { await reload() }
        .onChange(of: recorder.isRecording) { _, _ in Task { await reload() } }
    }

    /// File system work stays off the main thread, so a slow disk or a pending permission never freezes the app.
    private func reload() async {
        let list = await Task.detached(priority: .userInitiated) {
            MeetingActions.recentMeetings().map { (url: $0, size: MeetingActions.sizeText($0)) }
        }.value
        meetings = list
        loading = false
    }

    private func row(_ folder: URL, _ size: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.lastPathComponent)
                    .font(Theme.body(11.5)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(size)
                    .font(Theme.mono(9)).foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 6)
            pill("Claude") { MeetingActions.sendToClaude(folder) }
            pill("Codex") { MeetingActions.sendToCodex(folder) }
            GlyphButton(symbol: "folder", size: 10, box: 22) { MeetingActions.reveal(folder) }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.ink4.opacity(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline, lineWidth: 1))
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(Theme.label(8.5)).tracking(1)
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
