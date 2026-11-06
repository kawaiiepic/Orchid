# Orchid TestFlight setup

Orchid is a **separate iOS application** from Petal. It shares the Apple
developer team but requires its own App ID, App Store Connect app record,
and App Store distribution provisioning profile.

## App identity

- App name: **Orchid**
- Bundle ID: **dev.blossomvale.orchid**
- Apple team ID: **7H8MNYGZ49** (the team currently configured for Petal)
- Provisioning profile name: **Orchid**
- Flutter version in CI: **3.47.2**
- Build number: the unique GitHub Actions run number

## One-time Apple setup

1. In **Apple Developer > Certificates, Identifiers & Profiles > Identifiers**,
   register a new explicit App ID for `dev.blossomvale.orchid`.
2. In **App Store Connect > Apps**, create a new app named **Orchid**
   using this bundle ID. Select the correct platform (iOS).
3. In Apple Developer, create an **App Store / distribution provisioning
   profile** for Orchid. Name the profile **Orchid** exactly so the export
   options and CI validation agree.
4. Use an Apple Distribution certificate that is valid for the team.
   The certificate can be shared with Petal if still valid, but **the
   provisioning profile cannot**, because it is tied to Petal's bundle ID.

## GitHub Actions secrets

Set these under **Orchid repository > Settings > Secrets and variables >
Actions > New repository secret**. These secrets are repository-specific
unless stored in a shared organization configuration with the proper access.

| Secret | Purpose |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Base64-encoded Apple Distribution `.p12` |
| `P12_PASSWORD` | Password protecting the `.p12` file |
| `BUILD_PROVISION_PROFILE_BASE64` | Base64-encoded **Orchid** App Store `.mobileprovision` |
| `KEYCHAIN_PASSWORD` | Arbitrary strong password for temporary CI keychain |
| `APPSTORE_ISSUER_ID` | App Store Connect API issuer ID |
| `APPSTORE_API_KEY_ID` | App Store Connect API key ID |
| `APPSTORE_API_PRIVATE_KEY` | Contents of the matching `.p8` key |

The same App Store Connect API key and, if valid, the same Apple
Distribution certificate as Petal can be used. **Do not** copy Petal's
`BUILD_PROVISION_PROFILE_BASE64`; generate a new profile for Orchid.

Example for encoding certificates/profiles on macOS:

```bash
base64 -i distribution.p12 | pbcopy
base64 -i Orchid.mobileprovision | pbcopy
```

Copy each output to its corresponding GitHub Actions secret; do not
commit certificate files, provisioning profiles, or API keys.

## Build and upload

1. Open **Orchid > Actions > Orchid iOS / TestFlight**.
2. Select **Run workflow** on the `main` branch.
3. Leave **Upload signed iOS build to TestFlight** enabled and run.
4. If the build passes signing and export, GitHub Actions uploads the IPA.
5. In App Store Connect, wait for the build to finish processing under
   **TestFlight**, then add the relevant internal testers. External
   testing may require Apple's beta-app review.

A normal push to `main` builds an IPA for inspection but **does not
upload it** unless the commit message includes `[testflight]`.
Pull requests run the unsigned iOS build without signing secrets.

## Troubleshooting

- **Bundle ID mismatch:** ensure the new Apple ID, provisioning profile
  and Xcode bundle ID all use `dev.blossomvale.orchid`.
- **No matching provisioning profile:** verify the GitHub secret contains
  Orchid's profile, not Petal's, and its display name is `Orchid`.
- **Signing identity missing:** check that the `.p12`, its password,
  and certificate validity match your Apple team.
- **App Store upload rejected:** verify that Orchid exists in App Store
  Connect with this exact bundle ID and the API key has suitable access.
- **Dart/Xcode build errors:** resolve compilation or iOS plugin
  incompatibilities before troubleshooting signing.
- **iOS requires macOS:** the workflow provides a GitHub-hosted macOS
  runner; the upload cannot be performed directly using the local Linux
  toolchain.

The repository configuration alone does not create the Apple
Developer App ID, App Store Connect record, signing credentials or
TestFlight invitations.
