# Google Play release pipeline

**Keep unrelated pending Play Console changes clear and coordinate publishing before every main push or manual release.** An automatic API edit commit can submit other pending Console changes. `ERROR_IF_IN_REVIEW` protects an active review, but does not protect unrelated changes that have not been submitted. Do not edit Console or use another publisher during a release. See [Google's Console/API concurrency guidance](https://developers.google.com/android-publisher/concurrency-considerations).

**Every push or merge to `main`, including a pipeline update, starts an internal release of that commit once signing and WIF trust are ready.** Opening a PR does not publish a build. Complete the owner checks and trust migration below before first enabling push releases; use the resulting run summary for the actual build number.

## What runs

- **Flutter CI** on pull requests and pushes to `main`: locked dependency install, release-helper unit tests, `flutter analyze --no-fatal-infos`, all Flutter tests, and a debug Android App Bundle build without release credentials. The throwaway debug version `0.0.0+1001` exercises Flutter's version overrides; it is not uploaded or a release candidate
- **Google Play release** on every push/merge to `main`: the same checks, a signed release AAB with an automatic build number, upload to **internal testing**, and a verified release artifact. Each push builds its head commit; local commits, other branches, PRs and tags do not publish
- **Google Play release** also remains manually dispatchable on `main`, with `expected_version_name` confirming the committed marketing version, such as `1.0.20`. Its build number is automatic too
- **Promote Google Play release**, separately dispatched on `main` with no inputs: select the latest successful internal-release run, verify its signed artifact, show the selected build, then wait for manual production approval
- Production promotes the exact internal version and SHA-256 recorded by that run, without rebuilding or uploading again. Approval authorizes a **100% production rollout**, not a staged rollout

Flutter is pinned to **3.41.9** (Dart 3.11.5), matching the checked-in framework dependency lockfile. Java is 17; the project retains its existing Android SDK 36, Gradle, AGP and Kotlin settings. Actions are pinned to full commit SHAs; Flutter action caches are disabled because its nested cache action is referenced by a floating tag.

The analyzer fails on errors and warnings. Existing `dart:html` and `Radio` deprecation infos remain visible without blocking this pipeline-only change; their migration is separate app work.

## Automatic build numbers

The marketing version comes from `pubspec.yaml`; its checked-in value remains `1.0.20+21`. Release builds override only the effective Android build number with **`BUILD_NUMBER_BASE + github.run_number`**, where the reviewed Python constant `BUILD_NUMBER_BASE` is **1000**. Flutter receives `--build-name` with the committed version name and `--build-number` with the calculated code. The workflow does not edit `pubspec.yaml`, commit version bumps, refresh assets or invoke `scripts/build_android_bundle.sh`.

Use the actual run summary for the effective version and build number. GitHub increments `run_number` for each new run of this workflow and keeps it unchanged on reruns; only `run_attempt` changes on a rerun. Failed or cancelled runs therefore leave normal gaps, and rerunning an old run never allocates a new code. See [GitHub run counters](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#github-context).

The helper rejects calculated codes above **2100000000**. Before uploading, it checks visible Play tracks, bundles and APKs and refuses a reused, stale or out-of-order code. Google Play remains the authority for historical reuse. It never substitutes `max + 1` or retries with a different code. If another publisher overtakes this range, or the workflow identity/counter is changed or reset, stop and review a larger `BUILD_NUMBER_BASE` migration against all prior Play codes before resuming; do not reset or lower the base casually.

The signed artifact includes `release.json` schema **2**, recording the effective version, AAB SHA-256, commit, run ID, event, `run_number`, `run_attempt` and `build_number_base`. Promotion validates those fields against the successful source run and downloaded AAB. Retained legacy manifests without a schema remain supported only for successful manual source runs, with their existing provenance/hash checks and the same exact-current-internal requirement.

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

Bind WIF trust to repository ID `1172146395`, owner ID `25873667`, repository `ryanroundhouse/legorganizer`, ref `refs/heads/main`, and the exact environment and workflow. Internal uses `google-play-internal` and `.github/workflows/google-play-release.yml`; production uses `google-play-production` and `.github/workflows/google-play-promote.yml`, both on `main`. Allow `push` or `workflow_dispatch` only for internal; production stays `workflow_dispatch` only.

The existing mapping is `google.subject = assertion.repository_id + ':' + assertion.environment`, so internal's mapped subject is `1172146395:google-play-internal` (production's is `1172146395:google-play-production`). Preserve the exact subject-based service-account binding. GitHub's default `repo:…:environment:…` OIDC `sub` is **not** this deployment's mapped Google subject. Use only the minimum impersonation role required by the official guide; an unrestricted repository/branch binding would trust unintended workflows.

For **each environment**, add these non-secret environment variables after its trust/permissions are configured:

| Variable | Value |
| --- | --- |
| `PLAY_WORKLOAD_IDENTITY_PROVIDER` | Full `projects/NUMBER/locations/global/workloadIdentityPools/POOL/providers/PROVIDER` identifier |
| `PLAY_SERVICE_ACCOUNT` | The appropriate scoped service account email |

The job obtains a short-lived access token with only the `androidpublisher` OAuth scope immediately before its Play calls. No service-account JSON key or permanent token is stored in GitHub, and no credential file is created. WIF still grants persistent trust; review and maintain it as security configuration.

### 5. One-time owner migration for automatic internal releases

The owner must explicitly make this security change outside the repository. These are instructions, not a change performed by this PR. Update **only** provider `github` in pool `legorganizer-internal`, project `moodful`. Leave the production provider, service-account IAM bindings, roles, issuer, audiences and attribute mappings unchanged.

First inspect the full current provider:

```sh
gcloud iam workload-identity-pools providers describe github \
  --project=moodful \
  --location=global \
  --workload-identity-pool=legorganizer-internal \
  --format=json
```

Confirm its condition already requires all six exact repository ID, owner ID, repository, ref, environment and workflow values below, with `assertion.event_name == 'workflow_dispatch'`. Confirm the subject mapping above, existing issuer/audiences, and the existing internal service account's exact subject binding. Record the current configuration for comparison. **If anything differs or there are additional restrictions, stop and review; do not overwrite or remove them with this example.**

Replace only the event predicate with `(assertion.event_name == 'push' || assertion.event_name == 'workflow_dispatch')`. This command supplies the complete condition while omitting all other update flags so their values are retained:

```sh
gcloud iam workload-identity-pools providers update-oidc github \
  --project=moodful \
  --location=global \
  --workload-identity-pool=legorganizer-internal \
  --attribute-condition="assertion.repository_id == '1172146395' && assertion.repository_owner_id == '25873667' && assertion.repository == 'ryanroundhouse/legorganizer' && assertion.ref == 'refs/heads/main' && assertion.environment == 'google-play-internal' && assertion.workflow_ref == 'ryanroundhouse/legorganizer/.github/workflows/google-play-release.yml@refs/heads/main' && (assertion.event_name == 'push' || assertion.event_name == 'workflow_dispatch')"
```

Read the provider again with the same `describe` command and compare before/after: only the event predicate should differ; verify the exact subject binding is unchanged too. Review the [official `update-oidc` reference](https://docs.cloud.google.com/sdk/gcloud/reference/iam/workload-identity-pools/providers/update-oidc). Clear/coordinate pending Console changes before merging the automation; if the old manual-only trust remains, push-triggered authentication fails safely rather than widening trust itself.

## Release procedure

1. Make and review the actual app changes separately. Change the marketing version in `pubspec.yaml` when desired; no per-release build-number edit is needed
2. **Before pushing or merging to `main`**, check the Play Console publishing overview. Finish or remove unrelated pending changes and coordinate with other publishers. The main push automatically starts the internal release after checks pass
3. For a manual internal release instead, run **Google Play release** in GitHub Actions, choose `main`, and enter only the exact marketing version in `expected_version_name`, such as `1.0.20`. It receives a new automatic build number just like a push run
4. Wait for the internal upload and complete run to succeed. Review the summary's source commit, full version/build number and AAB hash, and install and test the app from Google Play's internal track on a real device
5. When ready, open **Promote Google Play release**, choose `main`, and click **Run workflow**. There are no run-ID or version inputs. After acquiring the shared release lock, preflight automatically selects the latest successful internal-release run and verifies its retained signed artifact without rebuilding or uploading. The artifact must still be available (30-day retention)
6. **Review the specific selected build before approving.** The preflight summary identifies the source run, attempt, artifact ID, commit, full version/build number and AAB SHA-256; the production approval job also identifies the selected build and **100% rollout**. Confirm this exact build is the one you installed and tested. The marketing version alone is insufficient: multiple builds can all be named `1.0.20`. Reject/cancel if the selected build is untested or unsuitable
7. The named reviewer opens **Review deployments** in the promotion run and approves `google-play-production`. Approval authorizes a **100% production rollout**. Only after approval does the production job authenticate to Play and verify that the selected version is still the sole completed internal release with the exact bundle hash, and that production has no conflicting release. Preflight success verifies GitHub provenance and the downloaded artifact; it does not establish Play's live state
8. Check Play Console for review, managed publishing and actual user availability. A successful track commit is not proof that Play review has finished or every user can download it

### How the candidate is selected and pinned

“Latest” means the largest `run_number` among completed, successful `push` or `workflow_dispatch` runs on this repository's `main` for the exact **Google Play release** workflow. It does not mean the most recently updated or completed run; rerunning an older workflow cannot make it newer. Preflight reads the complete, unfiltered workflow-specific run history and filters locally, avoiding GitHub's filtered-history limit. Missing or incomplete history, inconsistent pagination, or malformed candidate metadata stops promotion.

Selection occurs once, at preflight start after the shared lock is acquired. Preflight re-fetches the selected source run around artifact resolution and stops if its attempt or successful status changes. It requires exactly one matching artifact from that run's latest attempt; a missing, expired or duplicate artifact stops promotion, with no fallback to an older run or attempt. It downloads that exact artifact ID and verifies its manifest, package, commit, run identity and AAB checksum. The full version comes from the validated manifest. The selected run ID, attempt, artifact ID, commit, version and hash are pinned before approval; waiting for a reviewer never selects a different build.

Both release workflows share concurrency group `google-play-release`, with `cancel-in-progress: false` and `queue: max`. One runs at a time, including while production waits for review, with up to 100 pending runs. Further arrivals are cancelled when full. Processing follows the order runs start waiting, which need not match push/dispatch or build-number order; stale runs fail the Play preflight. Queue limits, failed checks and platform failures mean successful publication of every push is not guaranteed. A different publisher or Console session is outside this lock. See [GitHub concurrency behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency).

**Any internal-track change can block the pinned candidate after approval.** The entire internal track must contain exactly one completed release with only the selected version code, and its Play bundle hash must match. An additional, newer or draft internal release stops promotion. Production already containing that version or a higher code, or any draft, halted or staged production release, also stops promotion. Coordinate main pushes while testing and dispatching; once promotion owns the shared lock, later workflow releases queue behind it. Never approve based only on the phrase “latest internal.”

## Failure and recovery

- **Missing signing/configuration:** complete environment setup; no upload occurs before the build and safety checks pass
- **Version reuse, stale or out-of-order run:** do not blindly rerun an upload; reruns keep the same code. Check Play Console. If the latest successful source run is still the exact current internal release, test it and start a new promotion dispatch; review the selected build before approving. If the source run failed after an ambiguous commit, verify it in Console and handle promotion there after review. For a new upload, use a new main/manual run; if another publisher has overtaken the allocation range, review a larger-base migration first. Never retry with `max + 1`
- **Newer internal candidate:** start a new promotion dispatch after the newer internal run succeeds, then verify and test the newly selected build before approving. A newer failed run is excluded from selection, but if it partially committed to Play, the post-approval Play checks block an older candidate. There is no automatic retry or fallback; inspect Console and resolve the intended release deliberately
- **Ambiguous timeout after upload/commit:** inspect Play Console before retrying; writes are deliberately not automatically retried. The AAB/version/hash manifest is kept as evidence
- **Production rejected, timed out, or rerun:** no production rollout is authorized by a failed gate. Promotion reruns are rejected early because approval history is run-level. Start a **new manual promotion run** for a new selection and fresh approval, and check its selected build again. Do not use **Re-run jobs**. An expired artifact stops selection rather than falling back; use a new internal build or a separately reviewed manual Play Console promotion
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
