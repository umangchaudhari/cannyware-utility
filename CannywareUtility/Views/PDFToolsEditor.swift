import SwiftUI
import UniformTypeIdentifiers

struct PDFToolsEditor: View {
    let mode: PDFToolMode
    @State private var model = PDFToolsModel()
    @State private var showImporter = false
    @State private var selectedPreview: PagePreviewItem?
    @State private var imagePreview: ImagePreviewItem?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button { showImporter = true } label: {
                        Label(model.pdf == nil ? "Choose PDF" : "Change PDF", systemImage: "folder")
                    }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: !model.isBusy)).disabled(model.isBusy)
                    if let pdf = model.pdf {
                        pageControls(pdf)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135))], spacing: 14) {
                            ForEach(0..<pdf.pageCount, id: \.self) { index in
                                PDFPageCell(pdf: pdf, index: index, processor: model.processor,
                                            isSelected: model.selectedPages.contains(index),
                                            toggle: { model.toggle(index) },
                                            preview: { selectedPreview = PagePreviewItem(page: index) })
                            }
                        }
                        .id(pdf.id)
                        .disabled(model.isBusy)
                    } else if !model.isWorking {
                        ContentUnavailableView(mode.title, systemImage: "doc.richtext",
                                               description: Text("Choose a PDF to preview and select its pages."))
                    }
                    if let output = model.documentOutput { PDFOutputView(output: output).id(output.id) }
                    if !model.images.isEmpty { imageOutput.id("imageOutput") }
                }
                .frame(maxWidth: 1_000).padding(20).frame(maxWidth: .infinity)
            }
            .background(CannywareTheme.paper)
            .safeAreaInset(edge: .bottom) { actionBar }
            .task(id: model.documentOutput?.id) {
                guard let id = model.documentOutput?.id else { return }
                await Task.yield()
                withAnimation { proxy.scrollTo(id, anchor: .top) }
            }
            .onChange(of: model.images.count) { _, count in
                if count > 0 {
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation { proxy.scrollTo("imageOutput", anchor: .top) }
                    }
                }
            }
        }
        .navigationTitle(mode.title).navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): model.importFile(url, mode: mode)
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { model.errorMessage = error.localizedDescription }
            }
        }
        .sheet(item: $selectedPreview) { item in
            if let pdf = model.pdf {
                PageSelectionPreview(pdf: pdf, initialPage: item.page,
                                     selected: Binding(get: { model.selectedPages }, set: { model.select($0) }))
            }
        }
        .sheet(item: $imagePreview) { ImagePreviewSheet(item: $0) }
        .onDisappear { model.cancel() }
        .utilityError($model.errorMessage)
    }

    private func pageControls(_ pdf: ImportedPDF) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pdf.title).font(.headline).lineLimit(2)
            Text("\(model.selectedPages.count) of \(pdf.pageCount) pages selected")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button("Select all") { model.select(Set(0..<pdf.pageCount)) }
                Spacer()
                Button("Clear") { model.select([]) }
            }.disabled(model.isBusy)
        }
    }

    private var actionBar: some View {
        HStack {
            if model.isWorking {
                ProgressView(model.progress)
                Spacer()
                Button("Cancel") { model.cancel() }
            } else {
                Button { model.create(mode: mode) } label: {
                    Label(mode.action, systemImage: mode == .photos ? "photo.stack" : "doc.badge.plus")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: !model.isBusy && !model.selectedPages.isEmpty))
                .disabled(model.isBusy || model.selectedPages.isEmpty)
            }
        }
        .frame(maxWidth: 1_000).padding(16).frame(maxWidth: .infinity).background(.regularMaterial)
    }

    private var imageOutput: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Output · \(model.images.count) \(model.images.count == 1 ? "photo" : "photos")").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 12) {
                    ForEach(model.images) { image in
                        Button {
                            do { imagePreview = ImagePreviewItem(data: try Data(contentsOf: image.url), title: "Page \(image.page)") }
                            catch { model.errorMessage = error.localizedDescription }
                        } label: {
                            VStack(spacing: 8) {
                                ImageDataView(data: image.thumbnail).frame(height: 150)
                                Text("Page \(image.page)").font(.caption)
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(.plain).accessibilityLabel("Preview output for page \(image.page)")
                    }
                }
                Button { Task { await model.savePhotos() } } label: {
                    if model.isSaving { ProgressView("Saving…") }
                    else { Label(model.didSave ? "Saved to Photos" : "Download to Photos", systemImage: model.didSave ? "checkmark" : "arrow.down.to.line") }
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: !model.isBusy && !model.didSave))
                .disabled(model.isBusy || model.didSave)
                ShareLink(items: model.images.map(\.url)) {
                    Label("Share photos", systemImage: "square.and.arrow.up")
                }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

private struct PagePreviewItem: Identifiable {
    let id = UUID()
    let page: Int
}

private struct PDFPageCell: View {
    let pdf: ImportedPDF
    let index: Int
    let processor: PDFProcessor
    let isSelected: Bool
    let toggle: () -> Void
    let preview: () -> Void
    @State private var thumbnail: Data?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 8) {
            Button(action: preview) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.white)
                    if let thumbnail { ImageDataView(data: thumbnail).padding(4) }
                    else if failed { Image(systemName: "doc.richtext").font(.largeTitle).foregroundStyle(.gray) }
                    else { ProgressView() }
                }.frame(height: 175)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "magnifyingglass").padding(8).background(.regularMaterial, in: Circle()).padding(6)
                    }
            }
            .buttonStyle(.plain).accessibilityLabel("Preview page \(index + 1)")
            Button(action: toggle) {
                HStack {
                    Text("Page \(index + 1)").font(.subheadline)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(.title3)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Page \(index + 1), \(isSelected ? "selected" : "not selected")")
            .accessibilityHint("Double tap to change selection")
        }
        .padding(10)
        .background(isSelected ? CannywareTheme.mint : CannywareTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? CannywareTheme.forest : CannywareTheme.line, lineWidth: 1))
        .task {
            guard thumbnail == nil else { return }
            do { thumbnail = try await processor.thumbnail(pdf, page: index) }
            catch is CancellationError {}
            catch { failed = true }
        }
    }
}

private struct PageSelectionPreview: View {
    let pdf: ImportedPDF
    @Binding var selected: Set<Int>
    @State private var page: Int
    @Environment(\.dismiss) private var dismiss

    init(pdf: ImportedPDF, initialPage: Int, selected: Binding<Set<Int>>) {
        self.pdf = pdf
        _page = State(initialValue: initialPage)
        _selected = selected
    }

    var body: some View {
        NavigationStack {
            PDFCanvas(url: pdf.url, pageIndex: page)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 14) {
                        Button {
                            if selected.contains(page) { selected.remove(page) } else { selected.insert(page) }
                        } label: {
                            Label(selected.contains(page) ? "Selected" : "Select page", systemImage: selected.contains(page) ? "checkmark.circle.fill" : "circle")
                        }.buttonStyle(PrimaryButtonStyle())
                        HStack {
                            Button { page -= 1 } label: { Label("Previous", systemImage: "chevron.left") }.disabled(page == 0)
                            Spacer()
                            Text("\(page + 1) / \(pdf.pageCount)").font(.subheadline.monospacedDigit())
                            Spacer()
                            Button { page += 1 } label: { Label("Next", systemImage: "chevron.right") }.disabled(page == pdf.pageCount - 1)
                        }
                    }.padding(16).background(.regularMaterial)
                }
                .navigationTitle("Page \(page + 1)").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
