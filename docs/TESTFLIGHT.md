# TestFlight

`.github/workflows/testflight.yml` archives the app, signs it for the App Store and uploads it to
TestFlight. It runs when you start it by hand (Actions > TestFlight > Run workflow) or when you
push a tag such as `v0.2.0`, which also sets the version shown in TestFlight. It never runs on
pull requests, so forks of this public repository cannot reach the signing secrets. The build
number is the workflow's run number.

Nothing secret is committed: the certificate, its password and the App Store Connect key live
in GitHub repository secrets. The Team ID is not secret (it is inside every signed app).

## One-time setup (owner)

You need a paid Apple Developer Program membership. Steps 1 to 6 take about 20 minutes.

### 1. Team ID

developer.apple.com > Account > Membership details > Team ID (10 characters, such as
`A1B2C3D4E5`). Put it in `project.yml` as `DEVELOPMENT_TEAM` (so Xcode can sign for your
iPhone), or add it as the repository **variable** `APPLE_TEAM_ID`. The workflow uses the
variable first, then `project.yml`.

### 2. Identifiers

developer.apple.com > Certificates, Identifiers & Profiles > Identifiers > +:

1. **App Groups**: identifier `group.com.pjeziorowski.lumora`, description "Lumora".
2. **App IDs > App**: bundle ID (explicit) `com.pjeziorowski.lumora`, description "Lumora".
   Tick **App Groups**, save, then Edit > Configure next to App Groups and choose
   `group.com.pjeziorowski.lumora`.
3. **App IDs > App**: bundle ID `com.pjeziorowski.lumora.widgets`, description "Lumora
   Widgets", with the same App Group.

Shortcut: if you build the app once on your iPhone from Xcode with your team selected and
"Automatically manage signing" on, Xcode registers all three for you.

### 3. Distribution certificate (.p12)

On your Mac:

1. Xcode > Settings > Accounts > select your team > Manage Certificates > + > **Apple
   Distribution**.
2. Keychain Access > login > My Certificates > right-click "Apple Distribution: …" > Export >
   save as `distribution.p12` with a password.
3. In Terminal: `base64 -i distribution.p12 | pbcopy` copies it for step 6.

### 4. App record

appstoreconnect.apple.com > Apps > + > New App: platform iOS, name "Lumora" (the store name
must be unique; if it is taken, use something like "Lumora Photo Planner", the home-screen
name stays Lumora), primary language English (U.S.), bundle ID `com.pjeziorowski.lumora`,
SKU `lumora-ios`, full access.

### 5. App Store Connect API key

appstoreconnect.apple.com > Users and Access > Integrations > App Store Connect API > Team
Keys > + : name "Lumora CI", access **App Manager**. Download the `.p8` file (it can be
downloaded only once) and note the **Key ID** and the **Issuer ID** shown above the list.

The workflow uses the key to download or create the App Store provisioning profiles and to
upload builds. If the profile step fails with a permissions error, make a key with **Admin**
access instead.

### 6. Repository secrets

github.com/pjeziorowski/lumora > Settings > Secrets and variables > Actions > New repository
secret:

| Secret | Value |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | Key ID from step 5 |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from step 5 |
| `APP_STORE_CONNECT_PRIVATE_KEY` | The whole `.p8` file, including the BEGIN and END lines |
| `DISTRIBUTION_CERTIFICATE_P12_BASE64` | The base64 text from step 3 |
| `DISTRIBUTION_CERTIFICATE_PASSWORD` | The `.p12` password from step 3 |

Then delete the local `distribution.p12` and keep the `.p8` somewhere safe.

### 7. First build

Actions > TestFlight > Run workflow. After about 15 minutes for the run and 5 to 30 minutes
of processing, the build appears in App Store Connect > TestFlight. Create an internal group,
add yourself, and install it with the TestFlight app on your iPhone. Export compliance is
answered in the app (`ITSAppUsesNonExemptEncryption = NO`: the app only uses HTTPS), so builds
do not wait for that question.

## What the workflow does

1. Checks that every secret is set and names the missing ones.
2. Installs the distribution certificate into a temporary keychain (deleted at the end).
3. Downloads the App Store profiles for the app and the widget extension with fastlane's
   `get_provisioning_profile`, creating them if they do not exist yet.
4. Runs `xcodegen generate` with `LUMORA_APPSTORE_SIGNING=YES`, which merges
   `App/AppStoreSigning.yml` (manual signing with those profiles) into `project.yml`. Without
   that variable the project keeps automatic signing for local builds.
5. Archives the Release build and uploads it with `xcodebuild -exportArchive`
   (destination `upload`).

## Without CI

Once steps 1, 2 and 4 are done you can also upload from your Mac: `xcodegen generate`, open
`Lumora.xcodeproj`, choose "Any iOS Device", Product > Archive, then Distribute App > TestFlight
& App Store. Xcode signs automatically.
