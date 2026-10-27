# Releasing Nark

Use **Actions → Release → Run workflow** on `trunk`. Enter a version such as `0.1.0`, without `v`. Releases are drafts by default; clear that option to publish immediately.

The workflow tests Nark, builds an Intel/Apple Silicon app with Xcode 27.2, signs both the app and filter with Developer ID, notarizes it, and staples Apple's ticket before creating the ZIP. The release includes a SHA-256 checksum. It creates the `vVERSION` tag at the commit that was built and refuses to reuse an existing tag.

Build numbers use the repository's `CURRENT_PROJECT_VERSION` plus the workflow run number, followed by the attempt number, for example `26.1`. Keep the repository counter increasing. Each run or retry gets a distinct filter Mach service, so overlapping extension versions don't share an endpoint.

## One-time Apple setup

The Apple Development identity used for local builds cannot sign public releases. Create:

1. An exportable **Developer ID Application** certificate for the same Apple Developer team. Export the certificate **and private key** as a password-protected `.p12` from Keychain Access. A Developer ID Installer certificate isn't needed for ZIP distribution.
2. Two **Developer ID** provisioning profiles, both authorizing that certificate:
   - `com.ollieatkinson.Nark`: Network Extensions, System Extension installation, and app group `group.com.ollieatkinson.Nark`.
   - `com.ollieatkinson.Nark.Filter`: Network Extensions and the same app group.
3. An **App Store Connect team API key** for notarization. Keep its `.p8` private key, key ID and issuer ID. The workflow uses `notarytool`; it doesn't need an Apple ID password.

Both profiles must authorize `content-filter-provider-systemextension`. Development or App Store profiles won't work. The workflow checks the profile identifiers, team, certificate, capabilities and expiry before building.

Apple's guides: [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/), [Developer ID profiles](https://developer.apple.com/help/account/provisioning-profiles/create-developer-id-provisioning-profiles/), [notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## GitHub credentials

Create a repository environment named **`release`** under **Settings → Environments**. Restrict its deployment branches to `trunk`; add a required reviewer if you want a second approval before signing.

Set this environment variable:

| Variable | Value |
| --- | --- |
| `APPLE_TEAM_ID` | The ten-character Apple Developer team ID |

Add these **environment secrets**:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 of the certificate/private-key `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | The `.p12` export password |
| `APP_PROFILE_BASE64` | Base64 of the app's Developer ID `.provisionprofile` |
| `FILTER_PROFILE_BASE64` | Base64 of the filter's Developer ID `.provisionprofile` |
| `NOTARY_KEY_BASE64` | Base64 of the App Store Connect `.p8` key |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER_ID` | Its issuer ID |

On macOS, `base64 -i FILE | pbcopy` copies a file's encoded value. Paste it directly into the matching GitHub secret. Keep the original files and passwords outside the repository.

No personal GitHub token is needed by the workflow. Its built-in token can write releases only in the publishing job; the macOS signing job has read-only repository access. The signing keychain, private key files and installed profiles are removed at the end of the job.

## Package updates

The release runner approves only the reviewed macro/plugin revisions in [`package-trust`](package-trust). When updating one of those dependencies, review the new code and update its fingerprint alongside **both** `Package.resolved` files. The workflow fails if an approval no longer matches its pin; macro and plugin validation stay enabled.

## Before publishing

Download the ZIP from the draft release and test installation on a separate Mac. Move `Nark.app` to `/Applications`, run `nark activate`, and approve the system extension and network filter. Then publish the draft release on GitHub.

Notarization and Developer ID signing can't be tested end to end until the production credentials above are configured. Local development signing continues to use the existing development profiles.
