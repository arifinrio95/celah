import AppKit

/// Actions on saved meetings: list them, open them in Finder, and hand them to Claude or Codex.
enum MeetingActions {
    static let promptKey = "meeting.prompt"

    static let defaultPrompt = """
    These are the recordings of one meeting, in this folder:
    - mic.m4a: my voice
    - system.m4a: the other participants

    1. First, tell me whether you can access the audio. If you cannot, say so and ask me for a transcript.
    2. If you can, summarize the meeting in Indonesian: context, key points, decisions, action items with owner and due date when mentioned, and open questions.
    3. Save the result as summary.md in this folder.
    """

    static var prompt: String {
        let custom = UserDefaults.standard.string(forKey: promptKey) ?? ""
        return custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultPrompt : custom
    }

    /// Newest first. Folder names start with the date, so a reverse name sort is a date sort.
    static func recentMeetings(limit: Int = 30) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: MeetingRecorder.root, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return items.filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(limit)
            .map { $0 }
    }

    static func sizeText(_ folder: URL) -> String {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    /// Opens a new Claude Code session in the meeting folder with the prompt already filled in.
    /// The user only has to press Enter. Attached files are not sent this way; the folder is the working directory.
    static func sendToClaude(_ folder: URL) {
        var parts = URLComponents()
        parts.scheme = "claude"
        parts.host = "code"
        parts.path = "/new"
        parts.queryItems = [
            URLQueryItem(name: "prompt", value: prompt),
            URLQueryItem(name: "folder", value: folder.path),
        ]
        guard let url = parts.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Codex desktop has no prompt link, so the prompt goes to the clipboard and the app opens for a paste.
    static func sendToCodex(_ folder: URL) {
        let text = prompt + "\n\nFolder: " + folder.path
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        Apps.open(bundleID: "com.openai.codex")
    }

    static func reveal(_ folder: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
