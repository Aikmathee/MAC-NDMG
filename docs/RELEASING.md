# Releases

Every release builds separate Apple Silicon and Intel apps with an installed stable Xcode 26 on GitHub-hosted macOS runners. The build and verification steps both require macOS SDK 26+ so downloads include typed Liquid Glass controls. A release is published only after both builds, service tests, signature verification and packaging succeed. DMG and ZIP files include the app and installation instructions; Python is bundled. SHA256SUMS.txt covers all four downloads.

1. Update `VERSION`, `CHANGELOG.md`, and `docs/releases/v<version>.md`.
2. Run tests, commit and push `main`.
3. Push the matching version tag:

```sh
git tag v2.1.0
git push origin v2.1.0
```

The workflow validates the tag against VERSION, builds both architectures, creates a draft release, uploads all assets, then publishes it as latest. README download buttons use stable `releases/latest/download/` URLs. People downloading do not need a GitHub account or access to Actions artifacts.

If a release job fails, rerun the failed jobs from Actions. An unpublished draft can be reused; published releases are not overwritten. Change VERSION and create a new tag for a new version. Do not move an existing release tag.

Main branch pushes and pull requests build and test without publishing. Manual workflow runs also build without publishing; pushing a version tag publishes.

## Signing

The current pipeline uses ad-hoc signing and clearly labels the release as not notarized. A future Developer ID signing setup needs an Apple Developer account, a signing certificate and notarization credentials supplied as GitHub Actions secrets. They must never be committed. No signing credentials are currently configured.

## Developer ID and notarized builds

See [NOTARIZATION.md](NOTARIZATION.md) for read-only preflight, signing a separate copy, Apple submission and verified packaging. Signing/notarization are not enabled automatically by the normal release workflow. See [NETWORK_VALIDATION.md](NETWORK_VALIDATION.md) for controlled test coverage and real-network validation still required.
