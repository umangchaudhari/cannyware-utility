import SwiftUI

struct HomeView: View {
    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        CannywareBrand().padding(.vertical, 16)
                        Text("Choose a utility").font(.title2.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 18) {
                            NavigationLink { PhotoToolsView() } label: {
                                UtilityTile(title: "Photo", subtitle: "Compress · Photos to PDF", symbol: "photo.on.rectangle.angled")
                            }.accessibilityIdentifier("photoTools")
                            NavigationLink { PDFToolsView() } label: {
                                UtilityTile(title: "PDF", subtitle: "PDF to photos · Split PDF", symbol: "doc.richtext")
                            }.accessibilityIdentifier("pdfTools")
                        }
                        Label("Works on your device", systemImage: "iphone")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 900).padding(24).frame(maxWidth: .infinity)
                }
                .background(CannywareTheme.paper)
                .navigationTitle("Cannyware Utility")
                .toolbar(.hidden, for: .navigationBar)
            }.tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

private struct UtilityTile: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: symbol).font(.system(size: 35, weight: .medium))
                    .foregroundStyle(CannywareTheme.forest).frame(height: 50)
                HStack {
                    Text(title).font(.title2.bold())
                    Spacer()
                    Image(systemName: "chevron.right").font(.body.weight(.semibold))
                }
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(CannywareTheme.ink)
        }
    }
}

private struct PhotoToolsView: View {
    var body: some View {
        List {
            NavigationLink { CompressorView() } label: {
                Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left")
            }.accessibilityIdentifier("openCompressor")
            NavigationLink { PhotosToPDFView() } label: {
                Label("Photos to PDF", systemImage: "doc.badge.plus")
            }
        }
        .navigationTitle("Photo")
        .scrollContentBackground(.hidden).background(CannywareTheme.paper)
    }
}

private struct PDFToolsView: View {
    var body: some View {
        List {
            NavigationLink { PDFToolsEditor(mode: .photos) } label: {
                Label("PDF to photos", systemImage: "photo.stack")
            }
            NavigationLink { PDFToolsEditor(mode: .split) } label: {
                Label("Split PDF", systemImage: "scissors")
            }
        }
        .navigationTitle("PDF")
        .scrollContentBackground(.hidden).background(CannywareTheme.paper)
    }
}

struct SettingsView: View {
    var body: some View {
        List {
            Section {
                Label("On-device processing", systemImage: "iphone")
                Text("Photo compression and all PDF tools work locally. No processing APIs or uploads are used. Files already on your device work without internet.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Photos in iCloud and files in cloud storage may need internet to download before you can use them.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink("Privacy policy") { PrivacyPolicyView() }
                LabeledContent("App", value: "Cannyware Utility")
                LabeledContent("Version", value: version)
            }
        }
        .navigationTitle("Settings")
    }

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "1.0") (\(info["CFBundleVersion"] as? String ?? "2"))"
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section("Your files") {
                Text("Cannyware Utility processes photos and PDFs on your iPhone or iPad. The app does not send your files to a server or use an external processing API.")
                Text("There are no accounts, ads, analytics, or tracking SDKs. We do not collect your photos, documents, or personal information.")
            }
            Section("Access and saving") {
                Text("You choose photos with Apple's photo picker and PDFs with the Files picker. The app receives only the items you select. Download requests permission to add new images to Photos; it does not require access to your full photo library.")
                Text("Originals are not changed. PDF outputs can be saved to Files. Share sends a copy to the app or destination you choose, under that destination's privacy policy.")
            }
            Section("Local storage") {
                Text("Selected files, previews, and outputs are stored temporarily on your device so you can preview, save, and share them. Temporary files may remain until iOS clears them or you delete the app. Copies you save in Photos or Files remain there until you remove them.")
                Text("Compressed photos and photo-to-PDF images are created from image pixels without copying the source photo's EXIF or GPS metadata. Split PDFs retain the selected pages and may retain information embedded in those pages.")
            }
            Section("Offline use") {
                Text("All tools work without internet when the selected files are stored on your device. Apple's picker or a cloud storage provider may download cloud-only files first. Saving or sharing to a cloud destination can also require internet.")
            }
        }
        .navigationTitle("Privacy policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
