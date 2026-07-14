import SwiftUI
import Carbon

/// A button that shows the current global keyboard shortcut.
/// Clicking it enters "recording" mode: the next key combination (with at least
/// one modifier) is captured and saved. Escape cancels recording.
struct ShortcutRecorderButton: View {
    @State private var isRecording = false
    @State private var displayString = GlobalHotkeyMonitor.shared.displayString
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(isRecording ? "⌨ Recording…" : displayString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(isRecording ? .orange : .primary)
                    .frame(minWidth: 90)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isRecording
                                  ? Color.orange.opacity(0.15)
                                  : Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isRecording ? Color.orange : Color.primary.opacity(0.15),
                                            lineWidth: 1)
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: isRecording)
            }
            .buttonStyle(.plain)
            .help(isRecording ? "กด Esc เพื่อยกเลิก" : "คลิกเพื่อตั้งค่า shortcut ใหม่")

            // Reset to default button
            if displayString != GlobalHotkeyMonitor.shared.displayString ||
               GlobalHotkeyMonitor.shared.keyCode != GlobalHotkeyMonitor.defaultKeyCode {
                Button(action: resetToDefault) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("รีเซ็ตเป็น ⌃⌥C (ค่าเริ่มต้น)")
            }
        }
        .onAppear { displayString = GlobalHotkeyMonitor.shared.displayString }
    }

    // MARK: - Actions

    private func toggleRecording() {
        if isRecording {
            stopRecording(cancelled: true)
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        // Use a local monitor — works when Settings window is key (no Accessibility needed).
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Escape → cancel
            if event.type == .keyDown && Int(event.keyCode) == kVK_Escape {
                stopRecording(cancelled: true)
                return nil
            }
            // Only commit on keyDown with at least one modifier
            guard event.type == .keyDown,
                  !event.modifierFlags.intersection([.control, .option, .command, .shift]).isEmpty
            else {
                return event
            }

            let keyCode = Int(event.keyCode)
            let carbonMods = GlobalHotkeyMonitor.carbonModifiers(from: event.modifierFlags)
            save(keyCode: keyCode, carbonModifiers: carbonMods)
            stopRecording(cancelled: false)
            return nil   // consume the event
        }
    }

    private func stopRecording(cancelled: Bool) {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        displayString = GlobalHotkeyMonitor.shared.displayString
    }

    private func save(keyCode: Int, carbonModifiers: UInt32) {
        GlobalHotkeyMonitor.shared.update(keyCode: keyCode, carbonModifiers: carbonModifiers)
        displayString = GlobalHotkeyMonitor.shared.displayString
    }

    private func resetToDefault() {
        GlobalHotkeyMonitor.shared.resetToDefault()
        displayString = GlobalHotkeyMonitor.shared.displayString
    }
}
