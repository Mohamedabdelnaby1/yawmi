# Publishing Yawmi for direct Android download

The Android updater reads the latest published, stable GitHub release. Each release uses a tag in `vMAJOR.MINOR.PATCH` format, a higher Android version code, and the same signing certificate as the installed APK. Upload the universal APK as `Yawmi-Android.apk`, and provide `Yawmi-Android.apk.sha256` with the checksum. GitHub’s release API supplies the SHA-256 digest used by the app.

On Windows, build with the release channel enabled. Keep the signing key in local secure storage.

```powershell
./build-android.ps1 -GithubUpdates -PrivacyUrl 'https://mohamedabdelnaby1.github.io/yawmi/privacy.html'
```

The current direct-download channel preserves the original release certificate, which was generated as an Android debug signing key. Build this channel with that same key. Builds from other computers can use different debug certificates. Check the signer and alignment with Android SDK Build Tools before publication.

```sh
apksigner verify --print-certs Yawmi-Android.apk
zipalign -c -P 16 4 Yawmi-Android.apk
```

Create a draft release, attach the APK and checksum, and publish it as the latest stable release. The app checks for that release on launch and periodically. Source commits and drafts do not change the downloadable version. A store build uses the store’s update mechanism.

The Windows publishing script verifies the app ID, version, certificate, and alignment before uploading the APK and checksum to a draft. It then verifies the release assets before publishing. Run it after pushing the tested source to `main` with Git Credential Manager signed in.

```powershell
./tool/publish-github.ps1 -Apk ./outputs/Yawmi-1.5.0-Android.apk -NotesFile ./release-notes.md -BuildTools C:/Android/sdk/build-tools/36.0.0
```
