import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @State private var isRefreshing = false
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    private let providers: [LoginProvider] = [.claude]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("เชื่อมต่อบัญชีผู้ใช้งาน")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(providers) { provider in
                    Button(action: {
                        startLogin(provider: provider)
                    }) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 28, height: 28)
                                if provider.id == "claude", let logo = ClaudeLogo.image {
                                    Image(nsImage: logo)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: provider.logoSystemName)
                                        .foregroundColor(.orange)
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text("เข้าสู่ระบบด้วย \(provider.displayName)")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("ล็อกอินผ่านระบบเว็บเบราว์เซอร์ในแอป")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if isRefreshing {
                                ProgressView().controlSize(.small)
                            } else if store.hasSessionKey && provider.id == "claude" {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                }

                // Placeholder for future providers
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 28, height: 28)
                        Image(systemName: "plus.circle")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("บริการอื่นๆ ในอนาคต...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("ChatGPT, Gemini (เร็วๆ นี้)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
            }

            if store.hasSessionKey {
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                    Text("เชื่อมต่อสำเร็จแล้ว ข้อมูลเซสชันถูกเข้ารหัสเก็บไว้ในเครื่องนี้")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("การแสดงผลบน Menu Bar")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                HStack {
                    Text("ความกว้างแถบสถานะ: \(Int(store.barWidth))px")
                        .font(.system(size: 12))
                    Spacer()
                    Slider(value: $store.barWidth, in: 15...80, step: 1)
                        .frame(width: 160)
                }

                Toggle("แสดงแถบ Session ปัจจุบัน", isOn: $store.showSessionBar)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                Toggle("แสดงแถบโควตา รายสัปดาห์ (Weekly Limit)", isOn: $store.showWeeklyBar)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("การแจ้งเตือนและการเริ่มต้น")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                Toggle("แจ้งเตือนเมื่อโควตาใกล้เต็ม (80% / 95%) และเมื่อรีเซ็ต", isOn: $store.notificationsEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                Toggle("แจ้งเตือนเมื่อ Claude Code ทำงานเสร็จ", isOn: $store.sessionEndNotificationsEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                if LaunchAtLogin.isAvailable {
                    Toggle("เปิดแอปอัตโนมัติตอนเข้าสู่ระบบ", isOn: $launchAtLoginEnabled)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .onChange(of: launchAtLoginEnabled) { newValue in
                            do {
                                try LaunchAtLogin.set(newValue)
                                launchAtLoginError = nil
                            } catch {
                                launchAtLoginEnabled = LaunchAtLogin.isEnabled
                                launchAtLoginError = error.localizedDescription
                            }
                        }

                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                } else {
                    Text("เปิดอัตโนมัติตอน login ใช้ได้เฉพาะเมื่อรันจาก ClaudeUsageMenuBar.app (ผ่าน ./build_app.sh)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            HStack {
                if store.hasSessionKey {
                    Button("ล้างค่า / ออกจากระบบ", role: .destructive) {
                        clear()
                    }
                    .tint(.red)
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
    }

    private func startLogin(provider: LoginProvider) {
        LoginWebViewPresenter.shared.startLogin(provider: provider) {
            Task {
                isRefreshing = true
                await store.refresh()
                isRefreshing = false
            }
        }
    }

    private func clear() {
        SessionStore.shared.deleteSessionKey()
        SessionStore.shared.deleteOrganizationId()
        store.usage = nil
        store.errorMessage = nil
    }
}
