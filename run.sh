#!/bin/sh

set -xeu

APP_NAME="NEXGallery"
APP_DIR="$APP_NAME.app"

# 1. コンパイル (swiftcコマンドを使用)
echo "Compiling..."
swiftc *.swift -o $APP_NAME

# 2. .appディレクトリ構造の作成
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 3. 実行ファイルとInfo.plistの配置
mv $APP_NAME "$APP_DIR/Contents/MacOS/"
cp Info.plist "$APP_DIR/Contents/Info.plist"

# 4. アプリケーションの起動
echo "Launching..."
open "$APP_DIR"
