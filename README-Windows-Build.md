# Ervo-Browser iPhone – build an IPA from Windows

The supplied `.dmg` contained an Xcode/Swift source project, not a prebuilt iOS application. This folder preserves that project and includes a GitHub Actions workflow that builds it on a hosted macOS runner.

## Build the IPA without a Mac

1. Create a GitHub repository and upload **all contents of this folder**, including the hidden `.github` folder.
2. Open the repository on GitHub and select **Actions**.
3. Select **Build Ervo-Browser IPA** and click **Run workflow**.
4. When the run finishes successfully, open it and download the artifact named **ErvoBrowser-unsigned-IPA**.
5. Extract the artifact ZIP. It contains `ErvoBrowser-unsigned.ipa`.
6. On Windows, open Sideloadly, select that IPA, connect and unlock your iPhone, enter your Apple ID when prompted, and click **Start**. Sideloadly signs the app for your device and installs it.

## Important

- The workflow produces an **unsigned** IPA. It is not ready to install until Sideloadly (or another signing tool) signs it with your Apple ID/certificate.
- A free Apple ID normally gives a 7-day signing period; you must refresh/reinstall the app when it expires.
- This workflow has been prepared but could not be executed in this environment because it has no macOS, Xcode, or iOS SDK. The first GitHub Actions run is the actual build test.
- The app project declares iOS 17.0 as its deployment target.
- Do not share your Apple ID password or signing certificates with anyone. Enter credentials only in a trusted signing tool.
