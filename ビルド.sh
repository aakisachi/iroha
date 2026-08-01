#!/bin/zsh
# フォルダ色分けアプリのビルド → .appバンドル化 → 署名 → /Applications へ配置
set -e
cd "$(dirname "$0")"

APP_NAME="iroha"
EXE_NAME="FolderPainter"
BUNDLE_ID="app.folderpainter.FolderPainter"
DIST="dist/${APP_NAME}.app"

echo "==> リリースビルド"
swift build -c release

echo "==> バンドル組み立て"
rm -rf "$DIST"
mkdir -p "$DIST/Contents/MacOS" "$DIST/Contents/Resources"
cp ".build/release/$EXE_NAME" "$DIST/Contents/MacOS/"
cp "Resources/AppIcon.icns" "$DIST/Contents/Resources/"

cat > "$DIST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleExecutable</key><string>${EXE_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> 署名（Apple Development証明書を自動検出。ad-hoc禁止）"
IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/')
if [ -z "$IDENTITY" ]; then
    echo "エラー: Apple Development証明書が見つかりません（ad-hoc署名はTCC権限が飛ぶため禁止）"
    exit 1
fi
codesign --force --deep --sign "$IDENTITY" "$DIST"
codesign --verify --verbose "$DIST"

echo "==> /Applications へ配置"
pkill -x "$EXE_NAME" 2>/dev/null || true
ditto "$DIST" "/Applications/${APP_NAME}.app"

# Spotlightにビルド作業用コピーが二重表示されないよう、配置後はdistを消す
rm -rf dist

echo "完了: /Applications/${APP_NAME}.app"
echo "起動: open -a '${APP_NAME}'"
