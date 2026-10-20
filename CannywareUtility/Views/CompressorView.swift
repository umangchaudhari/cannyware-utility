import SwiftUI
import PhotosUI

struct CompressorView: View {
    @State private var model = CompressorModel()
    @State private var preview: ImagePreviewItem?
    @FocusState private var editingSize: Bool

    private let presets = [100, 200, 250, 500, 1_000]
    // Logarithmic travel keeps the common 10–1,000 KB range easy to adjust,
    // while the displayed value and precise input always remain in KB.
    private var sliderValue: Binding<Double> {
        Binding(get: { log10(Double(model.target?.bytes ?? 500_000) / 1_000) }, set: {
            model.targetText = String(Int(pow(10, $0).rounded()))
        })
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    photoCard
                    sizeCard
                    if let result = model.result {
                        resultCard(result).id("result")
                    }
                }
                .frame(maxWidth: 760)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(CannywareTheme.paper)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if model.isCompressing {
                        HStack {
                            ProgressView()
                            Text("Compressing…")
                            Spacer()
                            Button("Cancel") { model.cancelCompression() }
                        }
                        .padding(.vertical, 12)
                    } else {
                        Button {
                            editingSize = false
                            model.compress()
                        } label: { Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left") }
                        .buttonStyle(PrimaryButtonStyle(isEnabled: model.canCompress))
                        .disabled(!model.canCompress)
                        .accessibilityIdentifier("compressPhoto")
                    }
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
            .task(id: model.result?.id) {
                guard model.result != nil else { return }
                await Task.yield()
                withAnimation { proxy.scrollTo("result", anchor: .top) }
            }
        }
        .navigationTitle("Compress photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editingSize = false }
            }
        }
        .task(id: model.selectedItem) { await model.loadSelection() }
        .task {
            #if DEBUG
            await model.loadUITestPhoto()
            #endif
        }
        .onChange(of: model.targetText) { _, _ in model.clearResult() }
        .onDisappear { model.cancelCompression() }
        .sheet(item: $preview) { ImagePreviewSheet(item: $0) }
        .utilityError($model.errorMessage)
    }

    private var photoCard: some View {
        let loading = model.isLoading
        let pickerTitle = model.photo == nil ? "Choose photo" : "Change photo"
        return Card {
            VStack(spacing: 16) {
                if let photo = model.photo {
                    ImageDataView(data: photo.previewData)
                        .frame(maxHeight: 300)
                    HStack {
                        Text(FileSize.string(photo.data.count))
                        Spacer()
                        Text("\(photo.dimensions) · \(photo.format)")
                    }.font(.caption).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(CannywareTheme.forest)
                        .frame(height: 100).accessibilityHidden(true)
                }
                PhotosPicker(selection: $model.selectedItem, matching: .images, preferredItemEncoding: .current) {
                    if loading { ProgressView("Loading photo…") }
                    else { Label(pickerTitle, systemImage: "photo.on.rectangle") }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isBusy)
                .accessibilityIdentifier(model.photo == nil ? "choosePhoto" : "changePhoto")
            }
        }
    }

    private var sizeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                Text("Output size").font(.headline)
                HStack(alignment: .firstTextBaseline) {
                    TextField("500", text: $model.targetText)
                        .keyboardType(.numberPad)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .focused($editingSize)
                        .accessibilityLabel("Output size in kilobytes")
                        .accessibilityIdentifier("targetSize")
                    Text("KB").font(.title3).foregroundStyle(.secondary)
                }
                Slider(value: sliderValue, in: 1...log10(20_000))
                    .accessibilityLabel("Output size")
                    .accessibilityValue("\(model.targetText) KB")
                    .accessibilityIdentifier("targetSizeSlider")
                HStack { Text("10 KB"); Spacer(); Text("20,000 KB") }
                    .font(.caption).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { presetButtons }.fixedSize(horizontal: true, vertical: false)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 85))], spacing: 8) { presetButtons }
                }
                if model.target == nil {
                    Text("Enter 10–20,000 KB.").font(.caption).foregroundStyle(.red)
                }
                Text("JPEG at or below the selected size.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(model.isBusy)
        }
    }

    @ViewBuilder private var presetButtons: some View {
        ForEach(presets, id: \.self) { kb in
            Button(kb == 1_000 ? "1 MB" : "\(kb) KB") {
                editingSize = false
                model.setPreset(kb * 1_000)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(model.target?.bytes == kb * 1_000 ? CannywareTheme.mint : CannywareTheme.paper,
                        in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("preset\(kb * 1_000)")
        }
    }

    private func resultCard(_ result: CompressedPhoto) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Output").font(.headline)
                    Spacer()
                    Text(FileSize.string(result.data.count)).font(.headline)
                }
                Button { preview = ImagePreviewItem(data: result.data, title: "Compressed photo") } label: {
                    ImageDataView(data: result.previewData).frame(maxWidth: .infinity, maxHeight: 340)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .padding(10).background(.regularMaterial, in: Circle()).padding(8)
                        }
                }.buttonStyle(.plain).accessibilityLabel("Preview compressed photo")
                Text("\(result.dimensions) · JPEG · \(result.savedPercentage)% smaller")
                    .font(.caption).foregroundStyle(.secondary)
                Button { Task { await model.save() } } label: {
                    if model.isSaving { ProgressView("Saving…") }
                    else { Label(model.didSave ? "Saved to Photos" : "Download", systemImage: model.didSave ? "checkmark" : "arrow.down.to.line") }
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: !model.isSaving && !model.didSave))
                .disabled(model.isSaving || model.didSave)
                .accessibilityIdentifier("savePhoto")
                if let url = model.shareURL {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("sharePhoto")
                }
            }
        }
    }
}
