# legorganizer

Flutter app (Android + web). Android application ID: `com.gencorp.legorganizer`.

## Android / Google Play releases — read before touching versions or builds

**Releases are made by GitHub Actions, not by local builds.** Do not run
`scripts/build_android_bundle.sh` or `flutter build appbundle` to produce a
Play Store build; that script bumps `pubspec.yaml` and builds a locally signed
AAB that nobody uploads. Full pipeline docs: `docs/google-play-release.md`.

How it works:

- **Every push to `main`** runs `.github/workflows/google-play-release.yml`:
  analyze, test, build a signed release AAB, and upload it to the **internal
  testing** track. Build number is automatic (`1000 + github.run_number`);
  the `+N` suffix in `pubspec.yaml` is ignored for releases.
- **Production** is a separate manual step: dispatch
  `.github/workflows/google-play-promote.yml` on `main`
  (`gh workflow run google-play-promote.yml --ref main`). It picks the latest
  successful internal run and then **waits for a human to approve the
  `google-play-production` GitHub environment**. Claude cannot approve it.
  Approval rolls out to 100% of production.
- Target/compile SDK are set explicitly in `android/app/build.gradle`
  (`compileSdk = 36`, `targetSdk = 36`). Raise both there when Google Play's
  target API requirement increases.

Procedure for a new release:

1. Make the app change on a branch or on `main`. Only bump the *marketing*
   version in `pubspec.yaml` (`version: x.y.z+N`, change `x.y.z`) if you want a
   new version name; never hand-edit the build number for a release.
2. Push/merge to `main`. Confirm the "Internal Play push run" succeeds with
   `gh run list --workflow google-play-release.yml --limit 1`. The run log shows
   `VERSION_NAME` and `VERSION_CODE` actually uploaded.
3. Dispatch the promote workflow and tell the user to approve the
   production environment in GitHub Actions.
4. Before pushing to `main`, remind the user to clear unrelated pending Play
   Console changes (the API edit can submit them).

Local release signing (`android/key.properties`, `~/app-signing-key.jks`) is
only for local/manual testing builds.
