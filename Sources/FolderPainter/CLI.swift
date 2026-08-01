import SwiftUI
import Foundation

// テスト・デバッグ用のコマンドラインモード
// 使い方:
//   FolderPainter add <フォルダ> <色>     ルール追加して塗る（色: red/orange/yellow/green/blue/purple/pink/gray）
//   FolderPainter remove <フォルダ>       ルール削除して塗り直す
//   FolderPainter clear                  全ルール削除・全フォルダを元に戻す
//   FolderPainter status                 ルールと台帳の状況を表示
//   FolderPainter reconcile              手動で塗り直し（起動時スキャン相当）
//   FolderPainter render-icons <出力先>   8色のアイコンPNGを書き出す
@MainActor
func runCLI(_ args: [String]) -> Int32 {
    let store = RuleStore()
    store.load()

    func absolutize(_ raw: String) -> String {
        var p = (raw as NSString).expandingTildeInPath
        if !p.hasPrefix("/") {
            p = FileManager.default.currentDirectoryPath + "/" + p
        }
        return RuleStore.normalize(p)
    }

    func reconcileSync() {
        let result = ReconcileEngine.run(rules: store.rules, painted: store.painted)
        store.applyReconcileResult(painted: result.painted, skipped: result.skipped)
    }

    func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    switch args.first {
    case "add" where args.count == 3:
        let path = absolutize(args[1])
        guard isDirectory(path) else {
            print("エラー: フォルダが見つかりません: \(path)")
            return 1
        }
        guard let color = FolderColor.parse(args[2]) else {
            print("エラー: 色は #RRGGBB 形式（例 #FF6600）か、\(FolderColor.legacyNames.keys.sorted().joined(separator: "/")) を指定してください")
            return 1
        }
        guard let ino = ReconcileEngine.inode(of: path) else {
            print("エラー: フォルダ情報を取得できません: \(path)")
            return 1
        }
        store.addRule(path: path, color: color, inode: ino)
        reconcileSync()
        print("OK: \(path) を \(color.label) に設定。塗ったフォルダ: \(store.painted.count)個, スキップ: \(store.skipped.count)個")

    case "remove" where args.count == 2:
        let path = absolutize(args[1])
        store.removeRule(path: path)
        reconcileSync()
        print("OK: ルール削除。塗ったフォルダ: \(store.painted.count)個")

    case "clear":
        ReconcileEngine.unpaintAll(painted: store.painted)
        store.clearAllRulesAndPainted()
        print("OK: すべて解除しました")

    case "status":
        print("ルール: \(store.rules.count)件")
        for r in store.rules.sorted(by: { $0.path < $1.path }) {
            print("  [\(r.color.label)] \(r.path)")
        }
        print("塗ったフォルダ: \(store.painted.count)個")
        for e in store.painted.values.sorted(by: { $0.path < $1.path }) {
            print("  [\(e.color.label)] \(e.path)")
        }
        if !store.skipped.isEmpty {
            print("スキップ（元からカスタムアイコン）: \(store.skipped.count)個")
            for s in store.skipped { print("  \(s)") }
        }

    case "reconcile":
        reconcileSync()
        print("OK: 塗り直し完了。塗ったフォルダ: \(store.painted.count)個, スキップ: \(store.skipped.count)個")

    case "repaint":
        // 塗りエンジン更新後などに、台帳の全フォルダを現在の色で強制的に塗り直す
        var done = 0, failed = 0
        for entry in store.painted.values {
            guard isDirectory(entry.path),
                  let eff = ReconcileEngine.effectiveColor(for: entry.path, rules: store.rules) else { continue }
            if IconPainter.shared.paint(entry.path, color: eff) { done += 1 } else { failed += 1 }
        }
        reconcileSync()
        print("OK: \(done)個を塗り直しました" + (failed > 0 ? "（失敗: \(failed)個）" : ""))

    case "debug-icon" where args.count == 2:
        let p = absolutize(args[1])
        let painter = IconPainter.shared
        print("path: \(p)")
        print("customIcon(Icon\\r): \(painter.hasCustomIcon(p))")
        print("marker: \(painter.marker(p) ?? "なし")")
        print("silhouetteDiff: \(painter.silhouetteDiff(p))（12未満なら塗り残骸と判定）")
        print("台帳: \(store.painted[p]?.color.hex ?? "なし")")
        print("あるべき色: \(ReconcileEngine.effectiveColor(for: p, rules: store.rules)?.hex ?? "なし")")

    case "render-ui" where args.count == 2:
        // 設定画面を画像に描き出す（デザイン確認用）
        let view = SettingsView(store: store, coordinator: Coordinator(store: store), snapshotMode: true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("エラー: 描画に失敗しました")
            return 1
        }
        try? png.write(to: URL(fileURLWithPath: absolutize(args[1])))
        print("OK: \(absolutize(args[1])) に設定画面を書き出しました")

    case "render-icons" where args.count == 2:
        let dir = URL(fileURLWithPath: absolutize(args[1]))
        do {
            try IconPainter.shared.writePNGs(to: dir)
            print("OK: \(dir.path) に8色のPNGを書き出しました")
        } catch {
            print("エラー: \(error.localizedDescription)")
            return 1
        }

    default:
        print("""
        使い方:
          FolderPainter add <フォルダ> <色>     ルール追加（色: #RRGGBB か red/blue 等の色名）
          FolderPainter remove <フォルダ>       ルール削除
          FolderPainter clear                  全解除
          FolderPainter status                 状況表示
          FolderPainter reconcile              手動塗り直し
          FolderPainter render-icons <出力先>   アイコンPNG書き出し
        引数なしで起動するとメニューバー常駐アプリになります。
        """)
        return 1
    }
    return 0
}
