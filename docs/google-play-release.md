# Google Play release pipeline

This pipeline is **inactive for releases until the owner completes the setup below**.
Adding or merging it does not publish anything. No app version is changed automatically.

## What runs

- **Flutter CI** on pull requests and pushes to `main`: locked dependency install, release-helper unit tests, `flutter analyze --no-fatal-infos`, all Flutter tests, and a debug Android App Bundle build without release credentials
- **Google Play release**, manually dispatched on `main`: the same checks, signed release AAB, upload to **internal testing**, and a verified release artifact
- **Promote Google Play release**, separately dispatched on `main`: verify a successful internal run and its signed artifact, then wait for manual production approval
- Production promotes the exact internal version and SHA-256 recorded by that run, without rebuilding or uploading again. Approval authorizes a **100% production rollout**, not a staged rollout

Flutter is pinned to **3.41.9** (Dart 3.11.5), matching the checked-in framework dependency lockfile. Java is 17; the project retains its existing Android SDK 36, Gradle, AGP and Kotlin settings. Actions are pinned to full commit SHAs; Flutter action caches are disabled because its nested cache action is referenced by a floating tag.

The analyzer fails on errors and warnings. Existing `dart:html` and `Radio` deprecation infos remain visible without blocking this pipeline-only change; their migration is separate app work.

The workflow uses the version already committed in `pubspec.yaml`. It deliberately does not invoke `scripts/build_android_bundle.sh`, which increments versions and refreshes catalog assets.

## Owner setup (securely, outside this repository and chat)

### 1. Prepare Play Console

Confirm the existing app's application ID is **`com.gencorp.legorganizer`** and its Play App Signing/upload-key registration is correct. The app and its first release must already be set up in Play Console; complete any store listing, policy, tester, review and production-access requirements there. Configure internal testers before expecting testers to receive a build.

Keep the **existing upload keystore**. Do not replace the upload key or confuse it with Google's app-signing key. This pipeline does not create keys, users, grants or credentials.

### 2. Configure GitHub environments

In [repository environment settings](https://github.com/ryanroundhouse/legorganizer/settings/environments), create:

- `google-play-internal`: deployment branches must allow only the branch `main`
- `google-play-production`: deployment branches must be **Selected branches and tags**, with exactly one rule: branch `main`. Configure at least one **Required reviewer** and disable administrator bypass. Enable **Prevent self-review** if a different person must approve; leave it off if the owner intentionally dispatches and later approves their own release

Do not add release credentials at repository scope. Fork PRs and CI need no release secrets.

Production checks its reviewer and branch settings before promotion starts and again after the native approval gate. It also requires a recorded approval for that production environment and rejects reruns because approval history is run-level. Administrator bypass must be disabled and verifiably false. Missing settings, missing approvals, denied API reads, wrong branches and malformed responses stop the release. **An environment name alone is not an approval gate.** GitHub plan limitations may prevent required reviewers for a private repository; keep production disabled if protection is unavailable.

See [GitHub environment protection](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments), [environment API](https://docs.github.com/en/rest/deployments/environments#get-an-environment), and [approval history API](https://docs.github.com/en/rest/actions/workflow-runs#get-the-review-history-for-a-workflow-run).

### 3. Add existing signing credentials to internal environment only

Use GitHub's secure secret fields yourself. Never paste values into chat, a commit, issue, PR or workflow log.

| Environment secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the existing binary upload keystore, one line without a trailing newline |
| `ANDROID_KEYSTORE_PASSWORD` | Existing keystore password |
| `ANDROID_KEY_PASSWORD` | Existing upload-key password |
| `ANDROID_KEY_ALIAS` | Existing upload-key alias |

Add the internal **environment variable** `PLAY_UPLOAD_CERTIFICATE_SHA256`: the upload certificate SHA-256 fingerprint from Play Console's app integrity/signing page. Colons are accepted. The runner checks the keystore alias is a private key and matches this fingerprint before building.

The key and `android/key.properties` exist only on the ephemeral runner, with private file permissions, and are removed in an always-run cleanup step. Only the signed AAB and public release manifest are uploaded as a 30-day GitHub artifact. The artifact is accessible to people who can access Actions artifacts; do not bundle proprietary secrets into app assets.

### 4. Configure scoped Play authentication

Have the account owner/security administrator configure [Workload Identity Federation through a service account](https://github.com/google-github-actions/auth#workload-identity-federation-through-a-service-account) and the [Google Play Developer API](https://developers.google.com/android-publisher/getting_started). This is a persistent access/security change and must be done explicitly by the owner. This PR does not configure it.

Prefer separate existing service accounts for internal and production:

- Internal: access only to this app, with view app information and release-to-testing permissions; **no production-release permission**
- Production: access only to this app, with view app information and production-release permission; no account-wide administration or financial access

Bind the WIF trust to GitHub's exact numeric repository and owner IDs, `ryanroundhouse/legorganizer`, `refs/heads/main`, and the appropriate environment subject (`repo:ryanroundhouse/legorganizer:environment:google-play-internal` or `google-play-production`). Also restrict the workflow claim to `.github/workflows/google-play-release.yml` on `main` for internal, and `.github/workflows/google-play-promote.yml` on `main` for production. Use only the minimum service-account impersonation role required by the official guide. An unrestricted repository/branch trust would let modified workflows request credentials outside the intended release path.

For **each environment**, add these non-secret environment variables after its trust/permissions are configured:

| Variable | Value |
| --- | --- |
| `PLAY_WORKLOAD_IDENTITY_PROVIDER` | Full `projects/NUMBER/locations/global/workloadIdentityPools/POOL/providers/PROVIDER` identifier |
| `PLAY_SERVICE_ACCOUNT` | The appropriate scoped service account email |

The job obtains a short-lived access token with only the `androidpublisher` OAuth scope immediately before its Play calls. No service-account JSON key or permanent token is stored in GitHub, and no credential file is created. WIF still grants persistent trust; review and maintain it as security configuration.

## Release procedure

1. Make and review the actual app changes separately. Choose a new version/build number in `pubspec.yaml`, commit it, and merge reviewed code. Its Android version code must exceed all previously used Play version codes. The API preflight checks currently visible bundles/APKs/tracks; Google Play remains the authority for historical reuse
2. Check the Play Console publishing overview. Finish or remove unrelated pending changes before starting. Do not edit the Console or run another publisher while this workflow is active. A Play edit commit can submit other pending changes, so the owner must ensure the publishing queue contains only the intended release
3. In GitHub Actions, run **Google Play release**, choose `main`, and type the exact committed version, such as `1.0.20+21`. The example is illustrative; the pipeline does not choose or bump it
4. Wait for the internal upload and complete run to succeed. Review the summary's source commit, version and AAB hash, download the artifact if needed, and test the app from Google Play's internal track on a real device
5. When ready, manually run **Promote Google Play release** on `main`. Enter the successful internal workflow run ID (the number at the end of its Actions URL) and the exact tested version. This can happen later; it does not rebuild or upload the bundle. The original signed artifact must still be retained (30 days)
6. The promotion preflight verifies the source run is successful, manual, from this repository's `main`, and specifically the internal-release workflow. It downloads that run attempt's exact artifact, checks its source SHA, run ID, version, package and AAB checksum, and posts a review summary
7. The named reviewer opens **Review deployments** in the promotion run and approves `google-play-production` only after testing. Approval authorizes a **100% production rollout**. Reject/cancel if unsuitable. The production job rechecks the bundle hash/version against Play and refuses an existing draft, halted or staged production release rather than replacing it
8. Check Play Console for review, managed publishing and actual user availability. A successful track commit is not proof that Play review has finished or every user can download it

A single release concurrency group prevents overlapping runs from this workflow. GitHub can replace an older pending run with a newer one; do not queue multiple releases while a reviewer is testing. A different publisher or Play Console session is outside that lock.

## Failure and recovery

- **Missing signing/configuration:** complete environment setup; no upload occurs before the build and safety checks pass
- **Version reuse:** do not blindly rerun an upload. Check Play Console. If the version was already committed internally and the run succeeded, test that version and use **Promote Google Play release** with its run ID. If the source run failed after an ambiguous commit, verify the version manually in Play Console and handle its promotion there after review. Use a newly reviewed version for a genuinely new upload
- **Ambiguous timeout after upload/commit:** inspect Play Console before retrying; writes are deliberately not automatically retried. The AAB/version/hash manifest is kept as evidence
- **Production rejected, timed out, or rerun:** the tested internal version remains available. Promotion reruns are disabled because approval history is run-level. Start a **new promotion dispatch with the same successful internal run and version** for a fresh approval, without a new upload. An expired artifact needs a separately reviewed manual Play Console promotion
- **Existing review:** both internal and production commits set `changesInReviewBehavior=ERROR_IF_IN_REVIEW` and fail instead of cancelling the review. Wait for it to finish or handle it deliberately in Console; do not remove the guard. This does not detect unrelated changes that have not yet been submitted
- **Draft app / production access / policy requirements:** resolve the reported requirement in Play Console; the pipeline does not change the release to draft or relax Play requirements silently
- **No actual approval or unverifiable protections:** fix reviewer/branch settings or API visibility; never substitute a Boolean variable for review
- **GitHub runner SDK failure:** use the build log. Hosted runners supply Android tooling/licenses; there is no `yes | sdkmanager --licenses` step in this workflow

## Implementation and verification

`scripts/ci/release_support.py` uses the standard-library HTTPS client and the official Play API for [bundle uploads](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.bundles/upload), [SHA-256 identity](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.bundles), [track updates](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.tracks/update), validation and commits. The [commit API](https://developers.google.com/android-publisher/api-ref/rest/v3/edits/commit) documents a default that cancels an existing review; explicitly selecting `ERROR_IF_IN_REVIEW` is why upload/promotion use the small helper instead of an action that auto-commits without that option. Google documents [Console/API concurrency behavior](https://developers.google.com/android-publisher/concurrency-considerations).

Run offline safety tests with:

```sh
python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v
```

These tests mock network activity. They do not prove that signing secrets, WIF, Play permissions, device behavior or a real release work. A debug CI build also does not verify release signing. The first authorized internal release and subsequent approved promotion are the end-to-end tests after secure setup; no live release is needed to review this pipeline PR.
