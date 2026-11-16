# Contributing

Thank you for helping improve `scanner_bridge`.

## Before opening a pull request

1. Fork the repository and create a focused branch from `main`.
2. Keep changes provider-neutral unless a provider-specific implementation is
   required.
3. Never add service-account files, signing keys, tokens, device identifiers or
   other secrets.
4. Update public API documentation and `CHANGELOG.md` when appropriate.
5. Run the checks below from the repository root:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

cd example
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

For camera, lifecycle or provider changes, test the example on a physical
Android or iOS device and describe the result in the pull request.

## Pull requests

Keep each pull request focused and explain the compatibility impact. Include
the platforms and providers tested, permission changes, and any migration
steps. CI must pass before merge.

## Security reports

Do not disclose vulnerabilities in issues or pull requests. Follow
[`SECURITY.md`](SECURITY.md) instead.
