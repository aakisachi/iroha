import SwiftUI
import AppKit

// MARK: - 部品

// すりガラス背景（ウィンドウ全面）
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// 押した瞬間に沈むボタン（ポインタダウンで即応答・臨界減衰スプリング）
private struct SpringPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 1.0), value: configuration.isPressed)
    }
}

private struct PendingFolder: Identifiable {
    let path: String
    var id: String { path }
}

// MARK: - メイン画面

struct SettingsView: View {
    @ObservedObject var store: RuleStore
    let coordinator: Coordinator
    // ImageRenderer での静止画書き出し用（ScrollView等が描画できないため差し替える）
    var snapshotMode = false

    @State private var pendingFolder: PendingFolder?
    @State private var showClearConfirm = false

    private var sortedRules: [Rule] {
        store.rules.sorted { $0.path < $1.path }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            rulesArea

            footer
                .padding(16)
        }
        .frame(width: 520, height: 480)
        .background(
            Group {
                if snapshotMode {
                    Color(nsColor: .windowBackgroundColor)
                } else {
                    VisualEffectBackground()
                }
            }
            .ignoresSafeArea()
        )
        .sheet(item: $pendingFolder) { pending in
            AddColorSheet(path: pending.path) {
                pendingFolder = nil
            } onAdd: { color in
                addRule(path: pending.path, color: color)
                pendingFolder = nil
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 1.0), value: store.rules)
    }

    // CLIの画面書き出し時はNSAppが無いのでフォルダアイコンで代用
    private var appIcon: NSImage {
        if let app = NSApp { return app.applicationIconImage }
        return NSWorkspace.shared.icon(forFile: "/Applications/iroha.app")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("iroha")
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.4)
                Text("フォルダに彩りを。親の色は子へ受け継がれ、子の指定が優先されます。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var rulesArea: some View {
        Group {
            if sortedRules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("まだルールがありません")
                        .font(.system(size: 13, weight: .medium))
                    Text("「フォルダを追加」から、色を付けたいフォルダを選んでください。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshotMode {
                VStack(spacing: 2) {
                    ForEach(sortedRules) { rule in
                        RuleRow(rule: rule, store: store, coordinator: coordinator, snapshotMode: true)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(sortedRules) { rule in
                            RuleRow(rule: rule, store: store, coordinator: coordinator)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                pickFolder()
            } label: {
                Label("フォルダを追加", systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 4)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("すべて元に戻す", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 12))
            }
            .controlSize(.large)
            .disabled(store.rules.isEmpty && store.painted.isEmpty)
            .confirmationDialog("すべてのルールを削除して、塗ったフォルダを元のアイコンに戻します。よろしいですか？",
                                isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("すべて元に戻す", role: .destructive) { coordinator.clearAll() }
                Button("キャンセル", role: .cancel) {}
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("彩色中: \(store.painted.count)個")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if !store.skipped.isEmpty {
                    Text("スキップ: \(store.skipped.count)個（元からアイコン付き）")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
        }
        .buttonStyle(SpringPressStyle())
    }

    // MARK: - 操作

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "このフォルダに色を付ける"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = RuleStore.normalize(url.path)

        let count = ReconcileEngine.countDirs(under: path, stopAt: 3001)
        if count > 3000 {
            let alert = NSAlert()
            alert.messageText = "フォルダの数がとても多いです"
            alert.informativeText = "このフォルダの中には3000個を超えるフォルダがあります。すべてに色を付けると時間がかかることがあります。続けますか？"
            alert.addButton(withTitle: "続ける")
            alert.addButton(withTitle: "やめる")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }

        if ReconcileEngine.isCloudSynced(path) {
            let alert = NSAlert()
            alert.messageText = "共有・同期フォルダのようです"
            alert.informativeText = "Dropbox や iCloud Drive などの同期フォルダに色を付けると、共有相手のパソコンにも色付きアイコンが同期されることがあります。続けますか？"
            alert.addButton(withTitle: "続ける")
            alert.addButton(withTitle: "やめる")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }

        pendingFolder = PendingFolder(path: path)
    }

    private func addRule(path: String, color: FolderColor) {
        guard let ino = ReconcileEngine.inode(of: path) else { return }
        store.addRule(path: path, color: color, inode: ino)
        coordinator.scheduleReconcile(after: 0.1)
    }
}

// MARK: - ルール行

private struct RuleRow: View {
    let rule: Rule
    let store: RuleStore
    let coordinator: Coordinator
    var snapshotMode = false

    @State private var hovering = false

    private var colorBinding: Binding<Color> {
        Binding(
            get: { rule.color.color },
            set: { newValue in
                store.updateRuleColor(path: rule.path, color: FolderColor(nsColor: NSColor(newValue)))
                // ホイール操作中は連続で飛んでくるので、落ち着いてから塗り直す
                coordinator.scheduleReconcile(after: 1.0)
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            if snapshotMode {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rule.color.color)
                    .frame(width: 22, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            } else {
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .help("クリックでカラーホイールを開く")
            }

            VStack(alignment: .leading, spacing: 1) {
                Text((rule.path as NSString).lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                Text((rule.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(rule.path)

            Spacer()

            if hovering {
                Button {
                    store.removeRule(path: rule.path)
                    coordinator.scheduleReconcile(after: 0.1)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(SpringPressStyle())
                .help("このルールを削除（色は自動で元に戻ります）")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0))
        )
        .onHover { h in
            withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) { hovering = h }
        }
    }
}

// MARK: - 追加シート（ライブプレビュー付き）

private struct AddColorSheet: View {
    let path: String
    let onCancel: () -> Void
    let onAdd: (FolderColor) -> Void

    @State private var selected: Color = FolderColor.defaultColor.color

    private var chosen: FolderColor { FolderColor(nsColor: NSColor(selected)) }

    var body: some View {
        VStack(spacing: 14) {
            // 選んだ色がその場でフォルダアイコンに反映されるプレビュー
            Image(nsImage: IconPainter.shared.previewIcon(for: chosen))
                .resizable()
                .interpolation(.high)
                .frame(width: 110, height: 110)
                .shadow(color: chosen.color.opacity(0.35), radius: 16, y: 6)

            VStack(spacing: 2) {
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            ColorPicker(selection: $selected, supportsOpacity: false) {
                Text("色を選ぶ（クリックでカラーホイール）")
                    .font(.system(size: 12))
            }
            .padding(.top, 4)

            HStack {
                Button("キャンセル", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("この色で追加") { onAdd(chosen) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(22)
        .frame(width: 340)
    }
}
