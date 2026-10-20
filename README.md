# Cannyware Utility for iPhone and iPad

Native SwiftUI utilities for iOS/iPadOS 17 and later. All image and PDF processing runs locally with Apple's frameworks. No processing API, server, account, analytics, ads, or third-party SDK is used.

## Source and transparency

The project code is available under the [MIT license](LICENSE). See
[How to verify the privacy claims](TRANSPARENCY.md) for links from each claim to
its implementation, repeatable checks, and limitations. Source access makes the
claims inspectable; it does not replace review or establish that every distributed
binary matches the published source.

[Contributing](CONTRIBUTING.md) explains how to report issues and propose changes.
Apple frameworks and SF Symbols remain subject to Apple's terms; this project's
MIT license does not relicense Apple's resources.

## Tools

The home screen offers **Photo** and **PDF**. Settings and the privacy policy are in the bottom tab bar.

- **Photo → Compress:** choose a photo, use the KB slider or enter a precise value from 10 to 20,000 KB. Presets: 100 KB, 200 KB, 250 KB, 500 KB, and 1 MB (1,000 KB). Preview the output, tap **Download** to save a new image to Photos, or **Share**.
- **Photo → Photos to PDF:** select up to 50 photos, preview them, reorder or remove them, and create a PDF with one photo per page. Preview the PDF and use **Save to Files** or **Share PDF**.
- **PDF → PDF to photos:** choose a PDF, select any or all pages, preview pages at full size, and convert them to JPEGs. Preview the results and download them to Photos or share them together.
- **PDF → Split PDF:** choose a PDF, preview and select pages, and create a new PDF containing those pages in their original order. Text, rotation, and page annotations are retained. Save to Files or share.

Files already on the device work without internet. iCloud Photos and cloud file providers may need a connection to download the selected originals. Cloud save/share destinations can also require internet. There is no app-level iCloud sync or backend.

## Output behavior and limits

Compression targets are maximum sizes, not exact padded sizes. KB = 1,000 bytes and MB = 1,000,000 bytes. Each JPEG is measured and is at or below the selected target. The compressor searches JPEG quality and, when needed, reduces dimensions proportionally. Originals are never overwritten. Alpha is flattened onto white; animations and Live Photos produce a still image. Compressed JPEGs omit source EXIF/GPS metadata.

Image inputs are limited to 100 MB and 150 megapixels. Compression uses a maximum long edge of 8,192 pixels. Photos-to-PDF normalizes images to JPEGs with a maximum long edge of 3,000 pixels, applies orientation, and omits photo EXIF/GPS metadata. Each PDF page matches the photo's aspect ratio.

PDF inputs are limited to 100 MB and 500 pages. Locked PDFs and PDFs that forbid copying are rejected with an explanation. PDF-to-photos renders the visible crop box, rotation, and annotations onto white JPEGs with a 2,400-pixel long edge. Split PDFs copy pages without rasterizing them; information embedded in selected pages may remain.

Processing uses background actors. Multi-image work proceeds one image/page at a time. Files have unique temporary directories so subsequent results cannot overwrite files being shared. Temporary copies can remain until iOS clears them or the app is deleted. User-saved Photos/Files copies remain in those destinations.

## TestFlight handoff

Open `CannywareUtility.xcodeproj` and select the **Cannyware Utility** scheme. Select a generic iOS device, then **Product → Archive**. Upload the archive to the existing App Store Connect record. Keep the bundle identifier **com.cannyware.photos** and the existing development team; the user-facing name is **Cannyware Utility**. This update uses version **1.0**, build **2**. If build 2 has already been uploaded, increment the Build field before archiving.

These upload instructions are for the maintainer. Other developers can use the
unsigned build command below to inspect and compile the code, or select their own
Apple team and bundle identifier for a signed device build. The team and bundle
identifiers in the project are public identifiers, not signing credentials.

This update was developed without launching the app or a simulator. The unsigned Release build for iOS passed. Standalone checks of the shared processing code passed for photos-to-PDF, page ordering/selection, cropped/rotated pages, annotation retention, JPEG export, invalid input, cancellation, and compression limits. iPhone/iPad UI, Photos permission prompts, file pickers, and share sheets still need device testing.

Suggested device checks:

1. Compress a photo with each preset and a custom KB value; preview, download to Photos, and share.
2. Create a PDF from portrait and landscape photos; change page order; save and reopen it.
3. Import a PDF, preview pages, select a subset, and download the converted photos.
4. Split a PDF using both thumbnail selection and the full-screen preview's selection button.
5. Repeat with locally stored files in airplane mode and check iPad layouts and sharing.

## Development checks

Use a Mac with a compatible Xcode installation and the iOS SDK. The development
build was checked with Xcode 27.1; the app's minimum deployment target is iOS 17.

Build only (does not launch the app):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project CannywareUtility.xcodeproj -scheme 'Cannyware Utility' \
  -configuration Release -destination 'generic/platform=iOS' -sdk iphoneos \
  -derivedDataPath build/UtilitiesBuild -jobs 2 CODE_SIGNING_ALLOWED=NO build
```

Standalone macOS processing checks (no simulator or iOS app):

```sh
mkdir -p build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun --sdk macosx swiftc -parse-as-library -module-cache-path build/ProcessingModuleCache \
  -o build/check-pdf-processing \
  CannywareUtility/Models/PhotoModels.swift CannywareUtility/Models/DocumentModels.swift \
  CannywareUtility/Services/PhotoProcessor.swift CannywareUtility/Services/PDFProcessor.swift \
  scripts/check_pdf_processing.swift
./build/check-pdf-processing
```

The XCTest target also contains image-processing tests. UI tests have been updated for the new Photo → Compress navigation; they have not been run for this update. `scripts/create_project.py` adds source files to the project while preserving existing build and signing settings. `scripts/generate_icon.swift` generates the app icon from the same native tools symbol used inside the app.

The original `compress_photo.py` utility and Python environment remain independent of the iOS app.

## Repository hygiene

[.gitignore](.gitignore) excludes build products, test recordings, local Xcode
state, Python environments, signing material, and local secret files. It keeps
the Xcode project, shared schemes, app assets, tests, and dependency lockfiles
available for review. Put personal input files in `local-data/` and generated
exports in `exports/`; images and PDFs are not ignored globally because they may
be legitimate app assets or synthetic test fixtures.

An ignore rule does not remove a file already tracked by Git or erase history.
Review the files staged for a public commit. If a credential was previously
committed, removing the working copy is not enough: revoke the credential and
address the history before publishing.

License text: [MIT, Open Source Initiative](https://opensource.org/license/mit).
