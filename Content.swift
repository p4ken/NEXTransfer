import SwiftUI
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Models
struct DLNAImageItem: Identifiable, Hashable {
    let id: String
    let title: String
    let url: URL
}

// MARK: - ViewModel
@MainActor
class DLNAViewModel: ObservableObject {
    @Published var images: [DLNAImageItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let client = DLNAClient()
    
    func loadImages() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let items = try await client.fetchImages()
                self.images = items
            } catch {
                self.errorMessage = "エラー: \(error.localizedDescription)\nWi-Fi接続を確認してください。"
            }
            self.isLoading = false
        }
    }
}

// MARK: - View
struct ContentView: View {
    @StateObject private var viewModel = DLNAViewModel()
    
    let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]
    
    var body: some View {
        // NavigationViewは非推奨になりつつあるのでNavigationStackを使用（macOS 13+）
        // 古いmacOSの場合はNavigationViewに戻してください
        NavigationStack {
            VStack {
                if viewModel.isLoading {
                    ProgressView("カメラを探索中...")
                        .padding()
                } else if let error = viewModel.errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("再試行") { viewModel.loadImages() }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(viewModel.images) { item in
                                AsyncImage(url: item.url) { phase in
                                    switch phase {
                                    case .empty:
                                        Color.gray.opacity(0.2)
                                    case .success(let image):
                                        image.resizable().aspectRatio(contentMode: .fit)
                                    case .failure:
                                        Color.red.opacity(0.2).overlay(Text("読込失敗").font(.caption))
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                .frame(height: 120)
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("NEX Gallery")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { viewModel.loadImages() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600) // ウィンドウサイズ指定
        .onAppear { viewModel.loadImages() }
    }
}

// MARK: - DLNA Client Logic
class DLNAClient: NSObject {
    let baseURLString = "http://10.0.0.1:64321" 
    
    func fetchImages() async throws -> [DLNAImageItem] {
        let controlPath = try await getControlURL()
        let fullControlURL = controlPath.hasPrefix("http") ? URL(string: controlPath)! : URL(string: baseURLString + controlPath)!
        
        var images: [DLNAImageItem] = []
        try await browseRecursive(controlURL: fullControlURL, objectID: "0", images: &images)
        return images
    }
    
    private func getControlURL() async throws -> String {
        guard let url = URL(string: "\(baseURLString)/DmsDesc.xml") else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let parser = DeviceDescriptionParser(data: data)
        if let controlURL = parser.parse() { return controlURL }
        else { throw NSError(domain: "DLNA", code: 1, userInfo: [NSLocalizedDescriptionKey: "ContentDirectory not found"]) }
    }
    
    private func browseRecursive(controlURL: URL, objectID: String, images: inout [DLNAImageItem]) async throws {
        let soapBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
              <ObjectID>\(objectID)</ObjectID>
              <BrowseFlag>BrowseDirectChildren</BrowseFlag>
              <Filter>*</Filter>
              <StartingIndex>0</StartingIndex>
              <RequestedCount>100</RequestedCount>
              <SortCriteria></SortCriteria>
            </u:Browse>
          </s:Body>
        </s:Envelope>
        """
        
        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.httpBody = soapBody.data(using: .utf8)
        request.addValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.addValue("\"urn:schemas-upnp-org:service:ContentDirectory:1#Browse\"", forHTTPHeaderField: "SOAPAction")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let parser = BrowseResponseParser(data: data)
        let result = parser.parse()
        
        images.append(contentsOf: result.items)
        
        for containerID in result.containerIDs {
            try await browseRecursive(controlURL: controlURL, objectID: containerID, images: &images)
        }
    }
}

// MARK: - XML Parsers
class DeviceDescriptionParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var currentElement = "", tempControlURL = "", controlURL: String?
    private var foundServiceType = false
    
    init(data: Data) { self.parser = XMLParser(data: data); super.init(); self.parser.delegate = self }
    func parse() -> String? { parser.parse(); return controlURL }
    
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI n: String?, qualifiedName q: String?, attributes a: [String : String]) {
        currentElement = e; if e == "service" { foundServiceType = false; tempControlURL = "" }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) {
        if currentElement == "serviceType" && s.contains("ContentDirectory") { foundServiceType = true }
        if currentElement == "controlURL" { tempControlURL += s.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI n: String?, qualifiedName q: String?) {
        if e == "service" && foundServiceType { controlURL = tempControlURL; p.abortParsing() }
    }
}

class BrowseResponseParser: NSObject, XMLParserDelegate {
    struct Result { var items: [DLNAImageItem] = []; var containerIDs: [String] = [] }
    private let parser: XMLParser
    private var resultString = "", inResult = false
    
    init(data: Data) { self.parser = XMLParser(data: data); super.init(); self.parser.delegate = self }
    func parse() -> Result {
        parser.parse()
        guard let data = resultString.data(using: .utf8) else { return Result() }
        return DIDLLiteParser(data: data).parse()
    }
    
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI n: String?, qualifiedName q: String?, attributes a: [String : String]) { if e == "Result" { inResult = true } }
    func parser(_ p: XMLParser, foundCharacters s: String) { if inResult { resultString += s } }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI n: String?, qualifiedName q: String?) { if e == "Result" { inResult = false } }
}

class DIDLLiteParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var items: [DLNAImageItem] = [], containerIDs: [String] = []
    private var currentElement = "", currentID = "", currentResURL = "", isImage = false
    
    init(data: Data) { self.parser = XMLParser(data: data); super.init(); self.parser.delegate = self }
    func parse() -> BrowseResponseParser.Result { parser.parse(); return BrowseResponseParser.Result(items: items, containerIDs: containerIDs) }
    
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI n: String?, qualifiedName q: String?, attributes a: [String : String]) {
        currentElement = e
        if e == "container", let id = a["id"] { containerIDs.append(id) }
        if e == "item" { currentID = a["id"] ?? UUID().uuidString; currentResURL = ""; isImage = false }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) {
        let str = s.trimmingCharacters(in: .whitespacesAndNewlines); if str.isEmpty { return }
        if currentElement == "upnp:class" || currentElement == "class" { if str.contains("image") { isImage = true } }
        if currentElement == "res" { currentResURL += str }
    }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI n: String?, qualifiedName q: String?) {
        if e == "item" && isImage, let url = URL(string: currentResURL) { items.append(DLNAImageItem(id: currentID, title: "", url: url)) }
    }
}
