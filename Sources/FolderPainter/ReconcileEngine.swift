import Foundation

// 「あるべき色」と「今の色」の差分を計算して塗り直すエンジン。
// スレッドを問わず使えるよう、ルールと台帳のスナップショットを受け取り結果を返す。
enum ReconcileEngine {

    struct Result {
        var painted: [String: PaintedEntry]
        var skipped: [String]
    }

    static func effectiveColor(for path: String, rules: [Rule]) -> FolderColor? {
        var best: Rule?
        for r in rules where path == r.path || path.hasPrefix(r.path + "/") {
            if best == nil || r.path.count > best!.path.count { best = r }
        }
        return best?.color
    }

    static func run(rules: [Rule], painted: [String: PaintedEntry]) -> Result {
        let painter = IconPainter.shared
        let fm = FileManager.default
        var newPainted = painted
        var skipped: [String] = []

        // 1) 台帳にある場所の見直し（消えた・ゾーン外に出た・色が変わった）
        for (path, entry) in painted {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                newPainted.removeValue(forKey: path)
                continue
            }
            let eff = effectiveColor(for: path, rules: rules)
            if eff == nil {
                painter.unpaint(path)
                newPainted.removeValue(forKey: path)
            } else if eff != entry.color {
                // 塗りに成功した時だけ台帳を更新（失敗時は次回リトライさせる）
                if painter.paint(path, color: eff!) {
                    newPainted[path] = PaintedEntry(path: path, color: eff!, inode: entry.inode)
                }
            } else if painter.marker(path) == nil {
                // マーカー導入前に塗ったフォルダへ印を後付け
                painter.writeMarker(path, color: entry.color)
            }
        }

        // 2) ルール配下を走査して未塗装のフォルダを塗る
        for rule in rules {
            for dir in allDirs(underRoot: rule.path) {
                guard let eff = effectiveColor(for: dir, rules: rules) else { continue }
                if let existing = newPainted[dir] {
                    if existing.color != eff {
                        painter.paint(dir, color: eff)
                        newPainted[dir] = PaintedEntry(path: dir, color: eff, inode: existing.inode)
                    }
                } else {
                    // 台帳に無いのにカスタムアイコンが付いている場合:
                    // irohaの印（マーカー）付き or 見た目が「色違いの標準フォルダ」なら
                    // 過去の塗り残骸（コピー・移動の迷子）とみなして塗り直す。
                    // 本当にユーザー独自のアイコンだけスキップする。
                    if painter.hasCustomIcon(dir),
                       painter.marker(dir) == nil,
                       !painter.looksLikeTintedFolder(dir) {
                        skipped.append(dir)
                        continue
                    }
                    if painter.paint(dir, color: eff), let ino = inode(of: dir) {
                        newPainted[dir] = PaintedEntry(path: dir, color: eff, inode: ino)
                    }
                }
            }
        }

        return Result(painted: newPainted, skipped: skipped.sorted())
    }

    // 全解除: 台帳の全フォルダからアイコンを剥がす
    static func unpaintAll(painted: [String: PaintedEntry]) {
        for path in painted.keys {
            IconPainter.shared.unpaint(path)
        }
    }

    // root自身＋配下の全フォルダ（隠しフォルダと.appなどのパッケージは除外）
    static func allDirs(underRoot root: String) -> [String] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { return [] }

        var out = [root]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        if let en = fm.enumerator(at: URL(fileURLWithPath: root),
                                  includingPropertiesForKeys: keys,
                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in en {
                guard let rv = try? url.resourceValues(forKeys: Set(keys)),
                      rv.isDirectory == true, rv.isPackage != true else { continue }
                out.append(RuleStore.normalize(url.path))
            }
        }
        return out
    }

    // 登録前の規模チェック用（limitに達したら打ち切り）
    static func countDirs(under root: String, stopAt limit: Int) -> Int {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let en = FileManager.default.enumerator(at: URL(fileURLWithPath: root),
                                                      includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return 0 }
        var count = 0
        for case let url as URL in en {
            guard let rv = try? url.resourceValues(forKeys: Set(keys)),
                  rv.isDirectory == true, rv.isPackage != true else { continue }
            count += 1
            if count >= limit { return count }
        }
        return count
    }

    static func inode(of path: String) -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let num = attrs[.systemFileNumber] as? NSNumber else { return nil }
        return num.uint64Value
    }

    // Dropbox / iCloud Drive などの同期フォルダか（登録時の警告用）
    static func isCloudSynced(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        if path.hasPrefix(home + "/Library/Mobile Documents") { return true }
        let markers = ["Dropbox", "Google Drive", "OneDrive", "Box"]
        let components = path.split(separator: "/").map(String.init)
        return components.contains { c in markers.contains { c.hasPrefix($0) } }
    }
}
