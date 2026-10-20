# How to verify the privacy claims

This document links the app's privacy claims to code and describes checks that
someone else can repeat. Source availability lets people inspect the implementation;
it is not a security certification or proof that a particular distributed binary
was built from that source.

## Where to look

Paths below are relative to the repository root.

| Claim | Implementation to inspect |
| --- | --- |
| Photo compression runs on the device | [`PhotoProcessor.swift`](CannywareUtility/Services/PhotoProcessor.swift): `inspect`, `compress`, `thumbnail`, and `encode` use Image I/O and Core Graphics. |
| PDF creation, splitting, and conversion run on the device | [`PDFProcessor.swift`](CannywareUtility/Services/PDFProcessor.swift): `photosToPDF`, `split`, and `exportPhotos` use PDFKit, Core Graphics, and Image I/O. |
| Photos are selected through Apple's picker | [`CompressorView.swift`](CannywareUtility/Views/CompressorView.swift) and [`PhotosToPDFView.swift`](CannywareUtility/Views/PhotosToPDFView.swift) use `PhotosPicker`; their models load the chosen items. |
| PDF access is limited to files the user chooses | [`PDFToolsEditor.swift`](CannywareUtility/Views/PDFToolsEditor.swift) uses the Files importer. `importPDF` in the PDF processor opens security-scoped access, copies the input locally, and ends that access. |
| Saving photos requests add-only permission | [`PhotoLibrarySaver.swift`](CannywareUtility/Services/PhotoLibrarySaver.swift) requests `.addOnly` authorization and creates new assets. |
| App-owned intermediate files are local | [`DocumentModels.swift`](CannywareUtility/Models/DocumentModels.swift) and [`CompressorModel.swift`](CannywareUtility/Models/CompressorModel.swift) create uniquely named files under the app's temporary directory. |
| Photo outputs omit source EXIF/GPS metadata | The photo processor creates new JPEGs from rendered pixels without copying the original metadata dictionary. Photos-to-PDF uses those normalized images. |
| Sharing and saving PDFs are explicit user actions | [`ExportViews.swift`](CannywareUtility/Views/ExportViews.swift), the compression view, and the PDF editor expose `ShareLink`, the Files exporter, and download buttons. |
| The iOS app declares no tracking or collected data | [`PrivacyInfo.xcprivacy`](CannywareUtility/PrivacyInfo.xcprivacy) contains the declaration; [`Info.plist`](CannywareUtility/Info.plist) contains the Photos permission text. These declarations must be checked against behavior. |
| The iOS app currently has no third-party SDK dependencies | Inspect [`project.pbxproj`](CannywareUtility.xcodeproj/project.pbxproj), imports in the Swift sources, and [`create_project.py`](scripts/create_project.py). The separate Python command-line utility uses Pillow and pillow-heif; they are not shipped in the iOS app. |

## Repeatable checks

1. Build the checked-out source using the unsigned build command in
   [README.md](README.md#development-checks). Signing in to the author's Apple
   account is not required for that build.
2. Run the standalone processing checks from the README. They generate synthetic
   fixtures and exercise the actual photo/PDF services, including output limits,
   selected page order, rotations, annotations, invalid inputs, and cancellation.
   They do not inspect network traffic or prove the absence of all defects.
3. Review the image-processing tests in
   [`PhotoProcessorTests.swift`](CannywareUtilityTests/PhotoProcessorTests.swift).
   They cover file-size limits, image orientation, metadata removal, and other
   image cases. Running the Xcode test suite is a separate step.
4. For device testing, first save test photos and PDFs locally. Enable airplane
   mode and turn Wi-Fi off, then try each utility. Verify the saved files. This
   checks offline operation; it does not establish what happens when online.
5. To investigate online behavior, use network instrumentation while exercising
   a build from the source. Separate traffic from the app, Apple's system
   services, cloud file providers, and destinations selected in Share. Record the
   source revision, build, OS version, and actions so another person can repeat
   the observation.

A useful starting search for networking and dependency changes is:

```sh
rg -n 'URLSession|URLRequest|NWConnection|WebSocket|https?://|XCRemoteSwiftPackageReference|PBXShellScriptBuildPhase|\.package\(' \
  CannywareUtility CannywareUtility.xcodeproj scripts \
  -g '!**/xcuserdata/**'
```

Read any matches in context. For example, a plist's XML declaration contains an
HTTP URL without issuing a request. Conversely, an empty search result is not
proof that no networking is possible; review the code, dependencies, and runtime
behavior together.

## Boundaries of the claims

- **Cloud inputs and destinations:** Apple's picker or a file provider can
  download a cloud-only input. A user-selected sharing or saving destination can
  upload an output. Photos saved into a library with iCloud Photos enabled may
  sync through Apple's services. The app itself implements no sync service.
- **Temporary retention:** imported PDFs, normalized photos, previews, and outputs
  can remain in the app's temporary directory. The app does not currently provide
  a timed purge or a clear-cache control. iOS may clear temporary data; deleting
  the app removes its container. This is not a promise of immediate secure erasure.
- **Saved copies:** files explicitly saved to Photos or Files remain there until
  removed from that destination. Deleting the app does not remove those copies.
- **PDF metadata and content:** splitting copies selected pages and preserves
  their content and annotations. It is not a PDF sanitization or redaction tool.
  Information embedded in the pages can remain.
- **Device and platform trust:** the implementation relies on iOS, Apple's
  frameworks, and the device's protections. It does not implement a separate
  encrypted vault or protect files from a compromised operating system.
- **Source versus release:** this project has no independently verified,
  reproducible-build attestation or completed external security audit. A passing
  local build or processing check does not establish either.

## Release transparency

When publishing a release, identify the source commit or tag alongside the app
version and build number. Publish the relevant check results and disclose changes
to data handling or dependencies. Do not label a release independently audited
unless such an audit has actually been performed and its scope is available.

The current development handoff is version 1.0, build 2. Its unsigned iOS Release
build and standalone processing checks passed during development. The app and
simulator were not launched for that update; device UI and permission flows still
require testing. No external audit or runtime network inspection is claimed.
