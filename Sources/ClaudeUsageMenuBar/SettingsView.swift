import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore

    @State private var sessionKeyInput: String = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSucceeded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ตั้งค่า Session Key")
                .font(.headline)

            Text("""
            1. เปิด claude.ai ใน Chrome แล้วล็อกอินให้เรียบร้อย
            2. เปิด DevTools (⌘⌥I) > Application > Cookies > https://claude.ai
            3. คัดลอกค่าของ cookie ชื่อ "sessionKey" มาวางด้านล่าง

            ค่านี้จะถูกเก็บไว้ใน macOS Keychain บนเครื่องนี้เท่านั้น
            """)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            SecureField("sk-ant-sid01-...", text: $sessionKeyInput)
                .textFieldStyle(.roundedBorder)

            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundColor(testSucceeded ? .green : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(isTesting ? "กำลังทดสอบ..." : "บันทึกและทดสอบ") {
                    save()
                }
                .disabled(sessionKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)

                Button("ล้างค่า", role: .destructive) {
                    clear()
                }

                Spacer()

                Button("ปิด") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            sessionKeyInput = KeychainHelper.shared.readSessionKey() ?? ""
        }
    }

    private func save() {
        let trimmed = sessionKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainHelper.shared.saveSessionKey(trimmed)
        KeychainHelper.shared.deleteOrganizationId()

        isTesting = true
        testResult = nil
        Task {
            await store.refresh()
            isTesting = false
            if let errorMessage = store.errorMessage {
                testSucceeded = false
                testResult = errorMessage
            } else {
                testSucceeded = true
                testResult = "เชื่อมต่อสำเร็จ"
            }
        }
    }

    private func clear() {
        KeychainHelper.shared.deleteSessionKey()
        KeychainHelper.shared.deleteOrganizationId()
        sessionKeyInput = ""
        testResult = nil
        store.usage = nil
        store.errorMessage = nil
    }
}
