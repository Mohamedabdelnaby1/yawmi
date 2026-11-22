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

## Optional near-real-time release notifications

The direct-download build can receive release signals through Firebase Cloud Messaging. It checks GitHub for the actual stable release before offering an update. Android displays the system installer after Yawmi validates the APK.

1. Register Android package `app.yawmi.journal` in your Firebase project. Download its Android client configuration and pass it to the build locally as `-FirebaseConfig /path/to/google-services.json`.
2. Enable the Firebase Cloud Messaging API. Grant an authorized Google Cloud service account permission to send FCM messages. Set up GitHub Actions workload identity for this repository, restricting the provider to your repository, and give that identity permission to impersonate the service account.
3. Set the repository Actions variables `YAWMI_FCM_PROJECT_ID`, `YAWMI_FCM_WIF_PROVIDER` and `YAWMI_FCM_SERVICE_ACCOUNT`. The announcement workflow runs when a stable release with the expected APK and checksum is published. It sends the version only.
4. Test one configured build on Android with automatic updates and notification permission enabled. Publish a test release in a separate project or repository before enabling production announcements. The receiving device also needs internet and Google Play services.

Without a Firebase build configuration the automatic check runs while Yawmi is open, and Android schedules the background check. The system can delay background work or notifications.

The Windows publishing script verifies the app ID, version, certificate, and alignment before uploading the APK and checksum to a draft. It then verifies the release assets before publishing. Run it after pushing the tested source to `main` with Git Credential Manager signed in.

```powershell
./tool/publish-github.ps1 -Apk ./outputs/Yawmi-1.5.0-Android.apk -NotesFile ./release-notes.md -BuildTools C:/Android/sdk/build-tools/36.0.0
```
