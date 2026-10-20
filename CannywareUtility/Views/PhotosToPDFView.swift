import SwiftUI
import PhotosUI

struct PhotosToPDFView: View {
    @State private var model = PhotosPDFModel()
    @State private var preview: ImagePreviewItem?

    var body: some View {
        let pickerTitle = model.photos.isEmpty ? "Choose photos" : "Change photos"
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    PhotosPicker(selection: $model.selection, maxSelectionCount: 50, selectionBehavior: .ordered,
                                 matching: .images, preferredItemEncoding: .current) {
                        Label(pickerTitle, systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: !model.isBusy)).disabled(model.isBusy)
                    if model.isLoading { ProgressView(model.progress).padding() }
                    if !model.photos.isEmpty {
                        HStack {
                            Text("\(model.photos.count) \(model.photos.count == 1 ? "photo" : "photos")").font(.headline)
                            Spacer()
                            Text("One photo per page").font(.caption).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 14) {
                            ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                                photoCell(photo, index: index)
                            }
                        }.disabled(model.isBusy)
                    } else if !model.isLoading {
                        ContentUnavailableView("Photos to PDF", systemImage: "doc.badge.plus", description: Text("Select up to 50 photos. Arrange them in page order before creating the PDF."))
                    }
                    if let output = model.output { PDFOutputView(output: output).id(output.id) }
                }
                .frame(maxWidth: 900).padding(20).frame(maxWidth: .infinity)
            }
            .background(CannywareTheme.paper)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if model.isCreating {
                        ProgressView("Creating PDF…")
                        Spacer()
                        Button("Cancel") { model.cancel() }
                    } else {
                        Button { model.create() } label: { Label("Create PDF", systemImage: "doc.badge.plus") }
                            .buttonStyle(PrimaryButtonStyle(isEnabled: !model.isBusy && !model.photos.isEmpty))
                            .disabled(model.isBusy || model.photos.isEmpty)
                    }
                }.frame(maxWidth: 900).padding(16).frame(maxWidth: .infinity).background(.regularMaterial)
            }
            .task(id: model.output?.id) {
                guard let id = model.output?.id else { return }
                await Task.yield()
                withAnimation { proxy.scrollTo(id, anchor: .top) }
            }
        }
        .navigationTitle("Photos to PDF").navigationBarTitleDisplayMode(.inline)
        .task(id: model.selection) { await model.loadSelection() }
        .onDisappear { model.cancel() }
        .sheet(item: $preview) { ImagePreviewSheet(item: $0) }
        .utilityError($model.errorMessage)
    }

    private func photoCell(_ photo: PDFPhoto, index: Int) -> some View {
        VStack(spacing: 10) {
            Button {
                do { preview = ImagePreviewItem(data: try Data(contentsOf: photo.url), title: "Photo \(index + 1)") }
                catch { model.errorMessage = error.localizedDescription }
            } label: {
                ImageDataView(data: photo.thumbnail).frame(height: 155).frame(maxWidth: .infinity)
            }.buttonStyle(.plain).accessibilityLabel("Preview photo \(index + 1)")
            HStack {
                Text("Page \(index + 1)").font(.subheadline.weight(.medium))
                Spacer()
                Menu {
                    Button("Move earlier", systemImage: "arrow.up") { model.move(photo, by: -1) }.disabled(index == 0)
                    Button("Move later", systemImage: "arrow.down") { model.move(photo, by: 1) }.disabled(index == model.photos.count - 1)
                    Button("Remove", systemImage: "trash", role: .destructive) { model.remove(photo) }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel("Options for photo \(index + 1)")
            }
        }
        .padding(12).background(CannywareTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}
