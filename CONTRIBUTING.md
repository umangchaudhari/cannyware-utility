# Contributing

Read [README.md](README.md) for the build commands and tool behavior, and
[TRANSPARENCY.md](TRANSPARENCY.md) for the data flow and verification limits.

For a bug report, include the app version/build, device and OS version, steps to
reproduce, and expected and actual results. Use synthetic or non-sensitive sample
files. Remove personal photos, document content, local paths, and credentials from
anything shared publicly.

For a change:

1. Describe the behavior being changed and its effect on existing files and users.
2. Keep processing on the device. Any proposed network access, analytics,
   dependency, permission, or retention change needs explicit review and matching
   updates to the privacy documentation.
3. Add meaningful processing tests when behavior changes, and report which checks
   were actually run. Distinguish build checks from device testing.
4. Keep source, shared Xcode schemes, assets, and synthetic test fixtures in Git.
   Put personal inputs in `local-data/` and generated outputs in `exports/`, both
   ignored. Never commit signing credentials or private keys.
5. Use your own Apple team and a bundle identifier you control for signed device
   builds. Do not commit changes that replace the maintainer's signing settings.

Code contributions are accepted under the project's [MIT license](LICENSE).
