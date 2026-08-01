import Foundation
import Combine

// ユーザーが設定した「このフォルダ→この色」のルール
struct Rule: Codable, Identifiable, Equatable {
    var path: String
    var color: FolderColor
    var inode: UInt64 // 移動・改名の追跡用（ファイルの内部番号）
    var id: String { path }
}

// アプリが実際に塗ったフォルダの台帳エントリ
struct PaintedEntry: Codable, Equatable {
    var path: String
    var color: FolderColor
    var inode: UInt64
}

// ルールと台帳の保管庫。UI表示のため ObservableObject。
// 変更操作はメインスレッドから行う前提。
final class RuleStore: ObservableObject {
    @Published private(set) var rules: [Rule] = []
    @Published private(set) var painted: [String: PaintedEntry] = [:]
    @Published private(set) var skipped: [String] = [] // 既存カスタムアイコンでスキップした場所

    private(set) var paintedByInode: [UInt64: String] = [:]

    static let storeURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FolderPainter")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.json")
    }()

    private struct Snapshot: Codable {
        var rules: [Rule]
        var painted: [PaintedEntry]
    }

    // MARK: - 永続化

    func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        rules = snap.rules
        painted = Dictionary(uniqueKeysWithValues: snap.painted.map { ($0.path, $0) })
        rebuildInodeIndex()
    }

    func save() {
        let snap = Snapshot(rules: rules, painted: Array(painted.values))
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: Self.storeURL, options: .atomic)
        }
    }

    private func rebuildInodeIndex() {
        paintedByInode = Dictionary(painted.values.map { ($0.inode, $0.path) },
                                    uniquingKeysWith: { a, _ in a })
    }

    // MARK: - ルール操作

    func addRule(path: String, color: FolderColor, inode: UInt64) {
        let p = Self.normalize(path)
        rules.removeAll { $0.path == p }
        rules.append(Rule(path: p, color: color, inode: inode))
        save()
    }

    func removeRule(path: String) {
        let p = Self.normalize(path)
        rules.removeAll { $0.path == p }
        save()
    }

    func updateRuleColor(path: String, color: FolderColor) {
        guard let i = rules.firstIndex(where: { $0.path == path }) else { return }
        rules[i].color = color
        save()
    }

    // 改名・移動でルールフォルダ自体が動いたときの追従
    func moveRule(inode: UInt64, to newPath: String) {
        guard let i = rules.firstIndex(where: { $0.inode == inode }) else { return }
        let oldPath = rules[i].path
        rules[i].path = Self.normalize(newPath)
        // 配下に子ルールがあればそれも一緒に付け替える
        for j in rules.indices where rules[j].path.hasPrefix(oldPath + "/") {
            rules[j].path = newPath + rules[j].path.dropFirst(oldPath.count)
        }
        save()
    }

    // MARK: - 台帳操作

    func setPainted(_ entry: PaintedEntry) {
        painted[entry.path] = entry
        paintedByInode[entry.inode] = entry.path
    }

    func removePainted(_ path: String) {
        if let e = painted.removeValue(forKey: path) {
            paintedByInode.removeValue(forKey: e.inode)
        }
    }

    func movePainted(from oldPath: String, to newPath: String) {
        guard var e = painted.removeValue(forKey: oldPath) else { return }
        e.path = newPath
        painted[newPath] = e
        paintedByInode[e.inode] = newPath
    }

    func setSkipped(_ paths: [String]) {
        skipped = paths
    }

    // バックグラウンドの塗り直し結果を一括反映
    func applyReconcileResult(painted newPainted: [String: PaintedEntry], skipped newSkipped: [String]) {
        painted = newPainted
        rebuildInodeIndex()
        skipped = newSkipped
        save()
    }

    // 全解除（アイコンの除去は呼び出し側で済ませてから呼ぶ）
    func clearAllRulesAndPainted() {
        rules = []
        painted = [:]
        paintedByInode = [:]
        skipped = []
        save()
    }

    // MARK: - 色の決定（最近接先祖ルールが勝つ）

    func effectiveColor(for path: String) -> FolderColor? {
        var best: Rule?
        for r in rules where path == r.path || path.hasPrefix(r.path + "/") {
            if best == nil || r.path.count > best!.path.count { best = r }
        }
        return best?.color
    }

    static func normalize(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
