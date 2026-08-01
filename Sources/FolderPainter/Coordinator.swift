import Foundation
import AppKit

// ストア（メインスレッド）と塗り直しエンジン（バックグラウンド）の橋渡し役
final class Coordinator {
    let store: RuleStore

    private let workQueue = DispatchQueue(label: "folderpainter.reconcile", qos: .utility)
    private var pendingReconcile: DispatchWorkItem?
    private var reconcileRunning = false
    private var reconcileRequestedAgain = false

    init(store: RuleStore) {
        self.store = store
    }

    // MARK: - 塗り直しの実行（スナップショット→背景で塗る→結果をメインで反映）

    func scheduleReconcile(after delay: TimeInterval = 1.0) {
        pendingReconcile?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.runReconcile() }
        pendingReconcile = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func runReconcile(completion: (() -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        if reconcileRunning {
            reconcileRequestedAgain = true
            return
        }
        reconcileRunning = true
        let rules = store.rules
        let painted = store.painted
        workQueue.async { [weak self] in
            let result = ReconcileEngine.run(rules: rules, painted: painted)
            DispatchQueue.main.async {
                guard let self else { return }
                self.store.applyReconcileResult(painted: result.painted, skipped: result.skipped)
                self.reconcileRunning = false
                if self.reconcileRequestedAgain {
                    self.reconcileRequestedAgain = false
                    self.runReconcile()
                }
                completion?()
            }
        }
    }

    // MARK: - 全解除

    func clearAll(completion: (() -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        let painted = store.painted
        store.clearAllRulesAndPainted()
        workQueue.async {
            ReconcileEngine.unpaintAll(painted: painted)
            DispatchQueue.main.async { completion?() }
        }
    }

    // MARK: - FSEventsイベントの処理（移動・改名の追跡と再スキャン判定）

    func handleEvents(_ events: [FolderWatcher.Event]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var needsReconcile = false
            let home = NSHomeDirectory()

            for event in events {
                let flags = event.flags
                guard flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 else { continue }
                let path = RuleStore.normalize(event.path)

                // ノイズ除去: ~/Library 配下と隠しフォルダは対象外
                if path.hasPrefix(home + "/Library") { continue }
                if path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }

                // 改名・移動: inode（内部番号）が一致する既知フォルダなら台帳・ルールを追従させる
                if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0,
                   let ino = ReconcileEngine.inode(of: path) {
                    if let rule = self.store.rules.first(where: { $0.inode == ino }), rule.path != path {
                        self.store.moveRule(inode: ino, to: path)
                        needsReconcile = true
                    }
                    if let oldPath = self.store.paintedByInode[ino], oldPath != path {
                        self.store.movePainted(from: oldPath, to: path)
                        needsReconcile = true
                    }
                }

                // ルールゾーン内の出来事、または台帳に載っている場所の出来事なら再スキャン
                if self.store.effectiveColor(for: path) != nil || self.store.painted[path] != nil {
                    needsReconcile = true
                }
            }

            if needsReconcile {
                self.scheduleReconcile()
            }
        }
    }
}
