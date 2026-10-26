# Developer ID signing and Apple notarization

Status: tooling is prepared and tested with controlled subprocess fixtures. No Developer ID Application identity was available on the development Mac. The published 2.3.7 downloads remain ad-hoc signed and are **not notarized**. A successful real Apple submission and Gatekeeper-enabled clean-Mac launch are still required.

## Prerequisites

The account owner must have Apple Developer Program access, an existing **Developer ID Application** certificate with its private key in Keychain, and a `notarytool` Keychain profile. Set up credentials directly through Apple's tools; do not paste passwords, private keys, certificate exports or API keys into this repository or chat. The script neither creates accounts nor imports certificates.

Apple references:
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- https://developer.apple.com/documentation/security/customizing-the-notarization-workflow

## Read-only readiness check

```sh
python3 scripts/notarize_app.py --app dist/MacNDMG.app
```

This verifies the existing signature and reports installed Developer ID identities plus availability of `notarytool` and `stapler`. It does not sign, upload, store credentials or publish. `notarized: false` means this check does not establish notarization, even if a previously notarized app is checked.

## Sign and submit a copy

Use a fresh build with a **new release version**. Never replace assets of a published tag. Build and validate separately on Apple Silicon and Intel.

```sh
python3 scripts/notarize_app.py \
  --app dist/MacNDMG.app \
  --output build/notarized-new-release \
  --identity 'Developer ID Application: YOUR EXISTING IDENTITY' \
  --sign --submit --profile 'YOUR_EXISTING_KEYCHAIN_PROFILE'
```

The output folder must not exist. The script copies the app, signs nested Mach-O code and bundles from the inside out with a secure timestamp and hardened runtime, then verifies the embedded service on a clean configuration. It does not enable library-validation or unsigned-code exceptions.

The explicit `--submit` step uploads the app copy to Apple's notary service using the existing Keychain profile. Only an `Accepted` result proceeds to ticket stapling, ticket validation and Gatekeeper assessment. Failure leaves local output for inspection; it is not published. If submission times out, inspect the submission in Apple's tools before retrying. No account passwords are accepted by the script.

For signing alone, omit `--submit` and `--profile`. A signed copy alone is **not** a notarized release.

## Package the accepted copy

```sh
python3 scripts/package_release.py \
  --app build/notarized-new-release/MacNDMG.app \
  --output build/notarized-new-release/release \
  --notarized
```

`--notarized` requires stapler validation and Gatekeeper acceptance before packaging and changes the included installation note accordingly. The normal release pipeline remains ad-hoc until signing credentials are deliberately configured; it will not silently claim notarization.

Test the resulting downloads on a clean Mac with Gatekeeper enabled, including opening the app, reading live mounts, Finder-assisted sign-in and a noncritical test share. Keep results for both architectures. Publish only a new version after these checks; do not upload the notarization submission ZIP as the final installer.
