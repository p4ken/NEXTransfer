#!/usr/bin/env swift
import SwiftUI
import AppKit

// MARK: - 設定
// 画像があるフォルダのパス (カレントディレクトリを想定)
let imageDirectory = FileManager.default.currentDirectoryPath

// MARK: - SwiftUI View
struct ImageGridView: View {
   // フォルダ内のJPG/PNGを取得
   let imageUrls: [URL] = {
       let url = URL(fileURLWithPath: imageDirectory)
       let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
       return files?.filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) } ?? []
   }()

   // グリッドの設定 (幅150pxで埋め尽くす)
   let columns = [GridItem(.adaptive(minimum: 150))]

   var body: some View {
       ScrollView {
           LazyVGrid(columns: columns, spacing: 20) {
               ForEach(imageUrls, id: \.self) { url in
                   VStack {
                       // 画像の読み込みと表示
                       if let nsImage = NSImage(contentsOf: url) {
                           Image(nsImage: nsImage)
                               .resizable()
                               .scaledToFit()
                               .frame(height: 150)
                               .cornerRadius(8)
                       } else {
                           Text("読込失敗")
                       }
                       Text(url.lastPathComponent)
                           .font(.caption)
                   }
               }
           }
           .padding()
       }
       .frame(minWidth: 600, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
   }
}

// MARK: - アプリケーションの起動処理 (AppDelegate相当)
class AppDelegate: NSObject, NSApplicationDelegate {
   var window: NSWindow!

   func applicationDidFinishLaunching(_ notification: Notification) {
       // ウィンドウの作成
       window = NSWindow(
           contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
           styleMask: [.titled, .closable, .miniaturizable, .resizable],
           backing: .buffered, defer: false)
       window.center()
       window.title = "シンプル画像タイル"
      
       // SwiftUIのViewをホスティングしてセット
       window.contentView = NSHostingView(rootView: ImageGridView())
       window.makeKeyAndOrderFront(nil)
      
       // 前面に持ってくる
       NSApp.activate(ignoringOtherApps: true)
   }
  
   func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
       return true
   }
}

// MARK: - メイン実行部
let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
