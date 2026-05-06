import Foundation
import SwiftUI
import AppKit

// MARK: - Models
struct DLNAImageItem: Identifiable, Hashable {
  let id: String
  let title: String
  let lrgURL: URL?
  let smURL: URL?
  let tnURL: URL?
  let orgURL: URL?
}

// MARK: - Image Saver
@MainActor
class ImageSaver: ObservableObject {
  @Published var isSaving = false
  @Published var lastMessage: String?

  func saveImage(item: DLNAImageItem) {
    // Prefer saving from orgURL -> lrgURL -> smURL in that order
    guard let sourceURL = item.orgURL ?? item.lrgURL ?? item.smURL else {
      lastMessage = "No URL available to save"
      return
    }

    // Extract filename from the URL; use a default if missing
    let suggestedName = sourceURL.lastPathComponent.isEmpty ? "image.jpg" : sourceURL.lastPathComponent

    let panel = NSSavePanel()
    panel.title = "Save Image"
    panel.nameFieldStringValue = suggestedName
    panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    panel.allowedContentTypes = [.jpeg, .png, .rawImage, .image]
    panel.canCreateDirectories = true

    guard panel.runModal() == .OK, let destURL = panel.url else { return }

    isSaving = true
    lastMessage = nil

    Task {
      do {
        let (data, response) = try await URLSession.shared.data(from: sourceURL)
        // Check HTTP response status code
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
          throw URLError(.badServerResponse)
        }
        try data.write(to: destURL, options: .atomic)
        lastMessage = "✅ Saved: \(destURL.lastPathComponent)"
      } catch {
        lastMessage = "❌ Save failed: \(error.localizedDescription)"
      }
      isSaving = false
    }
  }
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
        self.errorMessage = "Error: \(error.localizedDescription)\nPlease check your Wi-Fi connection."
      }
      self.isLoading = false
    }
  }
}

// MARK: - View
struct ContentView: View {
  @StateObject private var viewModel = DLNAViewModel()
  @StateObject private var imageSaver = ImageSaver()

  let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Save status banner
        if imageSaver.isSaving {
          HStack {
            ProgressView()
              .scaleEffect(0.7)
            Text("Saving...")
              .font(.caption)
          }
          .padding(.vertical, 6)
          .padding(.horizontal, 12)
          .background(Color.accentColor.opacity(0.15))
          .frame(maxWidth: .infinity)
        } else if let msg = imageSaver.lastMessage {
          Text(msg)
            .font(.caption)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(msg.hasPrefix("✅") ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
            .frame(maxWidth: .infinity)
        }

        if viewModel.isLoading {
          ProgressView("Searching for camera...")
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
          VStack {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.largeTitle)
              .foregroundColor(.orange)
            Text(error)
              .multilineTextAlignment(.center)
              .padding()
            Button("Retry") { viewModel.loadImages() }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
              ForEach(viewModel.images) { item in
                ImageThumbnailView(item: item, isSaving: imageSaver.isSaving) {
                  imageSaver.saveImage(item: item)
                }
              }
            }
            .padding()
          }
        }
      }
      .navigationTitle("NEX-6 Wireless Transfer")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(action: { viewModel.loadImages() }) {
            Image(systemName: "arrow.clockwise")
          }
        }
      }
    }
    .frame(minWidth: 400, minHeight: 100)
    .onAppear { viewModel.loadImages() }
  }
}

// MARK: - Thumbnail View
struct ImageThumbnailView: View {
  let item: DLNAImageItem
  let isSaving: Bool
  let onTap: () -> Void

  @State private var isHovered = false

  var body: some View {
    ZStack(alignment: .bottom) {
      AsyncImage(url: item.smURL) { phase in
        switch phase {
        case .empty:
          Color.gray.opacity(0.2)
        case .success(let image):
          image.resizable().aspectRatio(contentMode: .fit)
          case .failure:
            Color.red.opacity(0.2)
              .overlay(Text("Load failed").font(.caption))
        @unknown default:
          EmptyView()
        }
      }
      .frame(height: 120)

      // Hover overlay
      if isHovered {
        HStack(spacing: 4) {
          Image(systemName: "arrow.down.circle.fill")
          Text("Save")
            .font(.caption2).bold()
        }
        .foregroundColor(.white)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
        .padding(.bottom, 6)
        .transition(.opacity)
      }
    }
    .cornerRadius(8)
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(isHovered ? Color.accentColor : Color.clear, lineWidth: 2)
    )
    .scaleEffect(isHovered ? 1.02 : 1.0)
    .animation(.easeOut(duration: 0.15), value: isHovered)
    .onHover { isHovered = $0 }
    .onTapGesture {
      guard !isSaving else { return }
      onTap()
    }
    .help("Click to save original-quality image")
    .disabled(isSaving)
  }
}

// MARK: - DLNA Client Logic
class DLNAClient: NSObject {
  let baseURLString = "http://10.0.0.1:64321"

  func fetchImages() async throws -> [DLNAImageItem] {
    let controlPath = try await getControlURL()
    let fullControlURL =
      controlPath.hasPrefix("http")
      ? URL(string: controlPath)! : URL(string: baseURLString + controlPath)!

    var images: [DLNAImageItem] = []
    try await browseRecursive(controlURL: fullControlURL, objectID: "0", images: &images)
    return images
  }

  private func getControlURL() async throws -> String {
    guard let url = URL(string: "\(baseURLString)/DmsDesc.xml") else { throw URLError(.badURL) }
    let (data, _) = try await URLSession.shared.data(from: url)
    let parser = DeviceDescriptionParser(data: data)
    if let controlURL = parser.parse() {
      return controlURL
    } else {
      throw NSError(
        domain: "DLNA", code: 1, userInfo: [NSLocalizedDescriptionKey: "ContentDirectory not found"]
      )
    }
  }

  private func browseRecursive(controlURL: URL, objectID: String, images: inout [DLNAImageItem])
    async throws
  {
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
    request.addValue(
      "\"urn:schemas-upnp-org:service:ContentDirectory:1#Browse\"", forHTTPHeaderField: "SOAPAction"
    )

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

  init(data: Data) {
    self.parser = XMLParser(data: data)
    super.init()
    self.parser.delegate = self
  }
  func parse() -> String? {
    parser.parse()
    return controlURL
  }

  func parser(
    _ p: XMLParser, didStartElement e: String, namespaceURI n: String?, qualifiedName q: String?,
    attributes a: [String: String]
  ) {
    currentElement = e
    if e == "service" {
      foundServiceType = false
      tempControlURL = ""
    }
  }
  func parser(_ p: XMLParser, foundCharacters s: String) {
    if currentElement == "serviceType" && s.contains("ContentDirectory") { foundServiceType = true }
    if currentElement == "controlURL" {
      tempControlURL += s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }
  func parser(
    _ p: XMLParser, didEndElement e: String, namespaceURI n: String?, qualifiedName q: String?
  ) {
    if e == "service" && foundServiceType {
      controlURL = tempControlURL
      p.abortParsing()
    }
  }
}

class BrowseResponseParser: NSObject, XMLParserDelegate {
  struct Result {
    var items: [DLNAImageItem] = []
    var containerIDs: [String] = []
  }
  private let parser: XMLParser
  private var resultString = "", inResult = false

  init(data: Data) {
    self.parser = XMLParser(data: data)
    super.init()
    self.parser.delegate = self
  }
  func parse() -> Result {
    parser.parse()
    guard let data = resultString.data(using: .utf8) else { return Result() }
    return DIDLLiteParser(data: data).parse()
  }

  func parser(
    _ p: XMLParser, didStartElement e: String, namespaceURI n: String?, qualifiedName q: String?,
    attributes a: [String: String]
  ) { if e == "Result" { inResult = true } }
  func parser(_ p: XMLParser, foundCharacters s: String) { if inResult { resultString += s } }
  func parser(
    _ p: XMLParser, didEndElement e: String, namespaceURI n: String?, qualifiedName q: String?
  ) { if e == "Result" { inResult = false } }
}

class DIDLLiteParser: NSObject, XMLParserDelegate {
  private let parser: XMLParser
  private var items: [DLNAImageItem] = [], containerIDs: [String] = []
  private var currentElement = "", currentID = "", isImage = false
  private var lrgURL: URL?, smURL: URL?, tnURL: URL?, orgURL: URL?
  private var currentResURL = ""

  init(data: Data) {
    self.parser = XMLParser(data: data)
    super.init()
    self.parser.delegate = self
  }
  func parse() -> BrowseResponseParser.Result {
    parser.parse()
    return BrowseResponseParser.Result(items: items, containerIDs: containerIDs)
  }

  func parser(
    _ p: XMLParser, didStartElement e: String, namespaceURI n: String?, qualifiedName q: String?,
    attributes a: [String: String]
  ) {
    currentElement = e
    if e == "container", let id = a["id"] { containerIDs.append(id) }
    if e == "item" {
      currentID = a["id"] ?? UUID().uuidString
      lrgURL = nil; smURL = nil; tnURL = nil; orgURL = nil
      currentResURL = ""
      isImage = false
    }
    if e == "res" { currentResURL = "" }
  }
  func parser(_ p: XMLParser, foundCharacters s: String) {
    let str = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if str.isEmpty { return }
    if currentElement == "upnp:class" || currentElement == "class" {
      if str.contains("image") { isImage = true }
    }
    if currentElement == "res" { currentResURL += str }
  }
  func parser(
    _ p: XMLParser, didEndElement e: String, namespaceURI n: String?, qualifiedName q: String?
  ) {
    if e == "res", let url = URL(string: currentResURL) {
      let path = url.path.uppercased()
      if path.contains("/LRG_") { lrgURL = url }
      else if path.contains("/SM_") { smURL = url }
      else if path.contains("/TN_") { tnURL = url }
      else { orgURL = url }
    }
    if e == "item" && isImage {
      items.append(DLNAImageItem(id: currentID, title: "", lrgURL: lrgURL, smURL: smURL, tnURL: tnURL, orgURL: orgURL))
    }
  }
}
