# VisionStream submission preparation

The original code is MIT licensed and can be shared/forked without paid Apple membership. Each distributor supplies their own public contact pages, team and registered identifier before App Store submission; the upstream source release does not invent a publisher identity. See `Docs/OPEN_SOURCE.md`.

This is a general-purpose WebKit browser with native immersive playback and optional local saving. These files prepare an honest submission; they do not certify compliance or submit anything to Apple.

## Free development and hosting

Xcode and simulator development are free. A free Apple Account/Personal Team permits personal-device testing, subject to seven-day provisioning. App Store and TestFlight distribution require Apple Developer Program membership, currently US$99/year or the local enrollment price. Enrollment is the owner's choice; none of these scripts enroll or purchase membership.

A separate public GitHub Pages repository can host only the support and privacy pages for free on a github.io HTTPS address. The app source, diagnostic reports, downloads and signing configuration do not belong in that repository. A purchased domain is optional. Cloudflare Pages' Free plan is another static-hosting option.

## Prepare owner details

Copy `Config/Publication.json.example` to `Config/Publication.json`. Fill in the actual publisher name, public support contact and intended public support/privacy URLs. Team ID and registered app identifier remain blank until the owner configures Apple signing. Do not put passwords, certificates, private keys or cookies in this file. The encryption declaration stays null until the bundled OpenSSL case is classified; do not guess false.

Run `python3 Scripts/prepare_submission.py`. It creates development drafts and explicitly lists pending fields. Only `Submission/Prepared/site/` contains the hosting files. When generated fixtures are available, it also includes a calibration page and two small original CC0 clips with explicit download permission; no external-site media is copied. Review the wording, identify the actual hosting provider and its request logging/privacy practices, replace all development notices, and publish that folder after approval. The privacy link must be public, work without an account, and describe the shipping build. GitHub Pages instructions: https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site

`metadata.json`, `ExportOptions.plist` and `preparation.json` are local release materials outside the site folder. Prepared drafts are excluded from the source package; regenerate with the included script. Do not upload the entire workspace to a hosting service.

## Signing and archive

The personal `VisionStream` scheme retains the existing bundle ID and installed data. `VisionStream-AppStore` uses AppStore configuration and optional owner-specific build settings, without changing the product's features. `prepare_submission.py --write-build-config` creates ignored publication build settings and a generated App Store Info.plist; an encryption answer is written only when provided explicitly. Generating project files preserves those settings.

Structural validation without an Apple account:

```
python3 Scripts/archive_app_store.py --unsigned --archive DerivedData/Archives/VisionStream-AppStore-validation.xcarchive
```

This archive cannot run on a headset or be submitted. Once a paid account, registered app ID, valid distribution certificate, classification and public details exist, run the same helper without `--unsigned` using a new archive path. Optional `--export PATH` exports locally; it never uploads. Xcode account sign-in and agreements must be handled by the owner directly. No account enrollment or automatic provisioning update is requested by the helper.

Run `python3 Scripts/app_store_preflight.py --archive PATH --output TestResults/app-store-preflight.json`. `--strict` returns a failure while any gate is pending. Source permissions, public URLs and physical acceptance are deliberately marked for human review; listing a document is not proof that permission covers this app. Preflight is a local audit, not Apple's validation or legal approval.

See `Download-policy.md`, `Dependency-review.md`, `Privacy-data-inventory.json` and `Review-guide.md`. Finish public hosting, source authorizations, export classification, physical headset checks, screenshots and the App Store Connect questionnaire before claiming readiness.

Official references checked 26 October 2026: https://developer.apple.com/help/account/membership/program-enrollment ; https://developer.apple.com/support/compare-memberships/ ; https://developer.apple.com/app-store/review/guidelines/ ; https://developer.apple.com/app-store/app-privacy-details/
