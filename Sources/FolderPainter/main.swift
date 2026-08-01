import AppKit

// 引数付きで起動 → CLIモード（テスト・デバッグ用）
// 引数なしで起動 → メニューバー常駐アプリ
let cliArgs = Array(CommandLine.arguments.dropFirst())
if !cliArgs.isEmpty {
    exit(MainActor.assumeIsolated { runCLI(cliArgs) })
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
