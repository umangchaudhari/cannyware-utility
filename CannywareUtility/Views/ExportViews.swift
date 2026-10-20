import SwiftUI
import PDFKit
import ImageIO
import UniformTypeIdentifiers

extension View {
    func utilityError(_ message: Binding<String?>) -> some View {
        alert("Unable to complete", isPresented: Binding(get: { message.wrappedValue != nil }, set: {
            if !$0 { message.wrappedValue = nil }
        })) { Button("OK", role: .cancel) { message.wrappedValue = nil } } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

struct ImageDataView: View {
    let data: Data
    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct ImagePreviewItem: Identifiable {
    let id = UUID()
    let data: Data
    let title: String
}

struct ImagePreviewSheet: View {
    let item: ImagePreviewItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZoomableImage(data: item.data)
                .background(CannywareTheme.paper)
                .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct ZoomableImage: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> ImageScrollView {
        let view = ImageScrollView()
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4_096
           ] as CFDictionary) {
            view.photo.image = UIImage(cgImage: image)
        }
        return view
    }
    func updateUIView(_ uiView: ImageScrollView, context: Context) {}
}

private final class ImageScrollView: UIScrollView, UIScrollViewDelegate {
    let photo = UIImageView()
    private var previousSize = CGSize.zero

    init() {
        super.init(frame: .zero)
        delegate = self
        addSubview(photo)
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = photo.image, bounds.width > 0, bounds.height > 0 else { return }
        if previousSize != bounds.size {
            previousSize = bounds.size
            zoomScale = 1
            photo.frame = CGRect(origin: .zero, size: image.size)
            contentSize = image.size
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            minimumZoomScale = scale
            maximumZoomScale = max(4, scale * 6)
            zoomScale = scale
        }
        contentInset = UIEdgeInsets(top: max(0, (bounds.height - contentSize.height) / 2), left: max(0, (bounds.width - contentSize.width) / 2), bottom: 0, right: 0)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { setNeedsLayout() }
}

struct PDFCanvas: UIViewRepresentable {
    let url: URL
    var pageIndex: Int? = nil

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = .secondarySystemBackground
        view.displayDirection = .vertical
        view.displayBox = .cropBox
        view.document = PDFDocument(url: url)
        view.displayMode = pageIndex == nil ? .singlePageContinuous : .singlePage
        view.autoScales = true
        if let pageIndex, let page = view.document?.page(at: pageIndex) { view.go(to: page) }
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
        if let pageIndex, let page = view.document?.page(at: pageIndex), view.currentPage != page {
            view.go(to: page)
            view.autoScales = true
        }
    }
}

struct PDFPreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            PDFCanvas(url: url)
                .navigationTitle("PDF preview").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    private let url: URL?
    private let data: Data?
    init(url: URL) { self.url = url; data = nil }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents
        url = nil
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let url { return try FileWrapper(url: url, options: .immediate) }
        return FileWrapper(regularFileWithContents: data ?? Data())
    }
}

struct PDFOutputView: View {
    let output: DocumentOutput
    @State private var showExporter = false
    @State private var showPreview = false
    @State private var saved = false
    @State private var errorMessage: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Output").font(.headline)
                    Spacer()
                    Text("\(output.pageCount) \(output.pageCount == 1 ? "page" : "pages")").foregroundStyle(.secondary)
                }
                PDFCanvas(url: output.url).frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 12))
                Button { showPreview = true } label: { Label("Full-screen preview", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { showExporter = true } label: { Label("Save to Files", systemImage: "arrow.down.to.line") }
                    .buttonStyle(PrimaryButtonStyle())
                ShareLink(item: output.url) { Label("Share PDF", systemImage: "square.and.arrow.up") }
                    .buttonStyle(SecondaryButtonStyle())
                if saved { Label("Saved to Files", systemImage: "checkmark").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .fileExporter(isPresented: $showExporter, document: ExportDocument(url: output.url), contentType: .pdf,
                      defaultFilename: output.url.deletingPathExtension().lastPathComponent) { result in
            switch result {
            case .success: saved = true
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { errorMessage = error.localizedDescription }
            }
        }
        .sheet(isPresented: $showPreview) { PDFPreviewSheet(url: output.url) }
        .utilityError($errorMessage)
    }
}

