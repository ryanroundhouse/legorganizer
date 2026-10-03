"""Fail-closed validation and Google Play promotion; no third-party dependencies."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.request

PACKAGE = "com.gencorp.legorganizer"
REPOSITORY = "ryanroundhouse/legorganizer"
PRODUCTION_ENVIRONMENT = "google-play-production"
MAX_VERSION_CODE = 2100000000
# Deliberately independent of pubspec's local build number and wall-clock time.
# Never lower this or reset/replace the release workflow without a reviewed migration.
BUILD_NUMBER_BASE = 1000
RELEASE_EVENTS = ("push", "workflow_dispatch")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def request_json(url, token, method="GET", payload=None, media=None):
    request = urllib.request.Request(
        url,
        data=media if media is not None else (None if payload is None else json.dumps(payload).encode()),
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json",
                 "Content-Type": "application/octet-stream" if media is not None else "application/json",
                 "User-Agent": "legorganizer-release"},
        method=method,
    )
    # Never print response bodies or credentials on an HTTP failure.
    try:
        with urllib.request.urlopen(request, timeout=900 if media is not None else 120) as response:
            data = response.read()
            return json.loads(data) if data else {}
    except urllib.error.HTTPError as error:
        raise ValueError(f"{method} {url.split('?')[0]} failed (HTTP {error.code})") from None


def github(path):
    return request_json(f"https://api.github.com/repos/{REPOSITORY}/{path}", os.environ["GH_TOKEN"])


def validate_environment(environment, policies):
    require(environment.get("name") == PRODUCTION_ENVIRONMENT, "Wrong production environment")
    require(environment.get("can_admins_bypass") is False, "Disable production administrator bypass first")
    reviewers = [rule for rule in environment.get("protection_rules", [])
                 if rule.get("type") == "required_reviewers" and rule.get("reviewers")]
    require(reviewers, "Production is disabled: configure required reviewers first")
    branch_policy = environment.get("deployment_branch_policy") or {}
    require(branch_policy.get("custom_branch_policies"), "Production must allow only the main branch")
    rules = policies.get("branch_policies", [])
    require(len(rules) == 1 and rules[0].get("name") == "main"
            and rules[0].get("type") == "branch", "Production branch policy must be exactly main (branch)")


def check_gate(approved=False):
    environment = github(f"environments/{PRODUCTION_ENVIRONMENT}")
    policies = github(f"environments/{PRODUCTION_ENVIRONMENT}/deployment-branch-policies")
    validate_environment(environment, policies)
    if approved:
        require(os.environ.get("GITHUB_RUN_ATTEMPT") == "1",
                "Production reruns are disabled; start a new approved release instead")
        history = github(f"actions/runs/{os.environ['GITHUB_RUN_ID']}/approvals")
        require(any(review.get("state") == "approved" and any(
            item.get("id") == environment["id"] for item in review.get("environments", []))
            for review in history), "No production environment approval recorded for this run")
    print("Production approval protections verified")


def source_version(root=Path(".")):
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$",
                      (root / "pubspec.yaml").read_text(), re.MULTILINE)
    require(match, "pubspec.yaml must have version x.y.z+positive_integer")
    require(int(match[2]) <= MAX_VERSION_CODE, "Android version code is too large")
    gradle = (root / "android/app/build.gradle").read_text()
    require(re.findall(r'applicationId\s*=\s*"([^"]+)"', gradle) == [PACKAGE],
            "Unexpected Android application ID")
    return match[1], int(match[2])


def output(values):
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as file:
        for key, value in values.items():
            file.write(f"{key}={value}\n")


def automatic_version_code(run_number):
    require(re.fullmatch(r"[1-9]\d*", str(run_number)), "Invalid workflow run number")
    code = BUILD_NUMBER_BASE + int(run_number)
    require(code <= MAX_VERSION_CODE, "Automatic build number exceeds Google Play's limit")
    return code


def release_identity():
    require(os.environ.get("GITHUB_REPOSITORY") == REPOSITORY, "Wrong repository")
    require(os.environ.get("GITHUB_REF") == "refs/heads/main", "Release only from main")
    require(os.environ.get("GITHUB_EVENT_NAME") in RELEASE_EVENTS, "Only main pushes or manual dispatches may release")
    name, _ = source_version()
    return name, automatic_version_code(os.environ["GITHUB_RUN_NUMBER"])


def preflight():
    name, code = release_identity()
    if os.environ["GITHUB_EVENT_NAME"] == "workflow_dispatch":
        require(os.environ.get("EXPECTED_VERSION_NAME") == name, "Version name confirmation does not match pubspec.yaml")
    output({"version_name": name, "version_code": code})
    print(f"Release candidate: {name}+{code} (build base {BUILD_NUMBER_BASE} + workflow run {os.environ['GITHUB_RUN_NUMBER']})")


def source_run():
    require(os.environ.get("GITHUB_REPOSITORY") == REPOSITORY, "Wrong repository")
    require(os.environ.get("GITHUB_REF") == "refs/heads/main", "Promote only from main")
    require(os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch", "Manual dispatch required")
    check_gate()
    run_id = os.environ["INTERNAL_RUN_ID"]
    require(re.fullmatch(r"[1-9]\d*", run_id), "Invalid internal workflow run ID")
    run = github(f"actions/runs/{run_id}")
    require(run.get("repository", {}).get("full_name") == REPOSITORY
            and run.get("head_branch") == "main" and run.get("event") in RELEASE_EVENTS
            and run.get("path") == ".github/workflows/google-play-release.yml"
            and run.get("status") == "completed" and run.get("conclusion") == "success",
            "Source must be a successful push/manual Google Play release run on this repository's main branch")
    name = f"play-aab-{run_id}-{run['run_attempt']}"
    artifacts = github(f"actions/runs/{run_id}/artifacts?per_page=100").get("artifacts", [])
    matches = [artifact for artifact in artifacts if artifact.get("name") == name and not artifact.get("expired")]
    require(len(matches) == 1, "Exactly one unexpired signed release artifact is required")
    require(re.fullmatch(r"[0-9a-f]{40}", run["head_sha"]), "Invalid source commit")
    require(type(run.get("run_number")) is int and run["run_number"] > 0
            and type(run.get("run_attempt")) is int and run["run_attempt"] > 0, "Invalid source run counters")
    output({"artifact_id": matches[0]["id"], "source_commit": run["head_sha"],
            "source_event": run["event"], "source_run_number": run["run_number"],
            "source_run_attempt": run["run_attempt"]})


def validate_manifest(candidate, data, expected_version, source_commit, run_id,
                      source_event, source_run_number, source_run_attempt):
    require(source_event in RELEASE_EVENTS and type(source_run_number) is int and source_run_number > 0
            and type(source_run_attempt) is int and source_run_attempt > 0, "Invalid source run metadata")
    require(candidate.get("package_name") == PACKAGE, "Unexpected artifact package")
    code = candidate.get("version_code")
    require(type(code) is int and 0 < code <= MAX_VERSION_CODE, "Invalid artifact version code")
    require(re.fullmatch(r"\d+\.\d+\.\d+", candidate.get("version_name", "")), "Invalid artifact version name")
    require(expected_version == f"{candidate['version_name']}+{code}", "Version confirmation differs from source artifact")
    require(candidate.get("commit") == source_commit and candidate.get("run_id") == run_id,
            "Artifact provenance differs from the verified source run")
    if type(candidate.get("schema_version")) is int and candidate["schema_version"] == 2:
        require(candidate.get("event") == source_event
                and type(candidate.get("run_number")) is int and type(candidate.get("run_attempt")) is int
                and candidate.get("run_number") == source_run_number
                and candidate.get("run_attempt") == source_run_attempt,
                "Artifact event or run counters differ from the verified source run")
        require(type(candidate.get("build_number_base")) is int and candidate["build_number_base"] >= 0
                and code == candidate["build_number_base"] + source_run_number,
                "Artifact build number does not match its recorded allocation")
    else:
        # Preserve the already published pre-automation manual release's artifact.
        require("schema_version" not in candidate and source_event == "workflow_dispatch",
                "Automatic sources require a versioned release manifest")
    require(candidate.get("sha256") == hashlib.sha256(data).hexdigest(), "Downloaded AAB checksum mismatch")
    return {"version_code": code, "sha256": candidate["sha256"]}


def verify_artifact():
    folder = Path("release-candidate")
    candidate = json.loads((folder / "release.json").read_text())
    values = validate_manifest(candidate, (folder / "app-release.aab").read_bytes(),
                               os.environ["EXPECTED_VERSION"], os.environ["SOURCE_COMMIT"], os.environ["INTERNAL_RUN_ID"],
                               os.environ["SOURCE_EVENT"], int(os.environ["SOURCE_RUN_NUMBER"]),
                               int(os.environ["SOURCE_RUN_ATTEMPT"]))
    output(values)
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
        summary.write(f"## Approval requested: 100% production rollout\n"
                      f"- Source run: https://github.com/{REPOSITORY}/actions/runs/{candidate['run_id']}\n"
                      f"- Version: `{candidate['version_name']}+{candidate['version_code']}`\n"
                      f"- Commit: `{candidate['commit']}`\n- AAB SHA-256: `{candidate['sha256']}`\n"
                      "Approve only after testing this version from the internal track.\n")


class Play:
    def __init__(self):
        self.token = os.environ["PLAY_ACCESS_TOKEN"]
        self.base = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}/edits"

    def call(self, path="", method="GET", payload=None):
        return request_json(self.base + path, self.token, method, payload)

    @contextmanager
    def edit(self):
        edit_id = self.call(method="POST", payload={})["id"]
        try:
            yield edit_id
        finally:
            # After a successful commit the edit is already gone. Do not hide other failures.
            try:
                self.call(f"/{edit_id}", "DELETE")
            except ValueError:
                pass


def version_codes(tracks):
    return [int(code) for track in tracks for release in track.get("releases", [])
            for code in release.get("versionCodes", [])]


def validate_new_version(tracks, bundles, apks, code):
    known = version_codes(tracks) + [int(item["versionCode"]) for item in bundles + apks]
    require(code > max(known, default=0), "Version code must exceed every currently visible Play version")
    internal = [track for track in tracks if track.get("track") == "internal"]
    require(all(release.get("status") == "completed" for track in internal for release in track.get("releases", [])),
            "Internal track has an unfinished release; resolve it in Play Console first")


def upload_internal(play, code, digest):
    aab = Path("build/app/outputs/bundle/release/app-release.aab").read_bytes()
    require(hashlib.sha256(aab).hexdigest() == digest, "AAB changed after manifest creation")
    with play.edit() as edit:
        tracks = play.call(f"/{edit}/tracks").get("tracks", [])
        bundles = play.call(f"/{edit}/bundles").get("bundles", [])
        apks = play.call(f"/{edit}/apks").get("apks", [])
        validate_new_version(tracks, bundles, apks, code)
        uploaded = request_json(
            f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}/edits/{edit}/bundles?uploadType=media",
            play.token, "POST", media=aab)
        require(int(uploaded["versionCode"]) == code and uploaded.get("sha256", "").lower() == digest,
                "Uploaded bundle version or SHA-256 differs from the release candidate")
        name, _ = source_version()
        play.call(f"/{edit}/tracks/internal", "PUT", {"track": "internal", "releases": [
            {"name": f"{name} ({code})", "versionCodes": [str(code)], "status": "completed"}]})
        play.call(f"/{edit}:validate", "POST")
        play.call(f"/{edit}:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW", "POST")
    verify_or_promote(play, code, digest)


def validate_internal(track, bundles, code, digest):
    releases = [release for release in track.get("releases", [])
                if release.get("status") == "completed"
                and release.get("versionCodes") == [str(code)]]
    require(track.get("track") == "internal" and len(releases) == 1,
            "Expected exact version is not a completed internal-testing release")
    matches = [bundle for bundle in bundles if int(bundle["versionCode"]) == code]
    require(len(matches) == 1 and matches[0].get("sha256", "").lower() == digest,
            "Google Play bundle SHA-256 does not match this run's signed AAB")
    return releases[0]


def production_release(source, current, code):
    require(current.get("track") == "production", "Unexpected production track")
    require(all(release.get("status") == "completed" for release in current.get("releases", [])),
            "Production has a draft, halted or staged release; resolve it in Play Console first")
    require(code > max(version_codes([current]), default=0), "Production version must increase")
    release = {key: source[key] for key in ("name", "releaseNotes", "inAppUpdatePriority") if key in source}
    release.update({"versionCodes": [str(code)], "status": "completed"})
    return {"track": "production", "releases": [release]}


def verify_or_promote(play, code, digest, promote=False):
    require(re.fullmatch(r"[0-9a-f]{64}", digest), "Invalid AAB SHA-256")
    with play.edit() as edit:
        internal = play.call(f"/{edit}/tracks/internal")
        bundles = play.call(f"/{edit}/bundles").get("bundles", [])
        source = validate_internal(internal, bundles, code, digest)
        if promote:
            current = play.call(f"/{edit}/tracks/production")
            desired = production_release(source, current, code)
            play.call(f"/{edit}/tracks/production", "PUT", desired)
            play.call(f"/{edit}:validate", "POST")
            play.call(f"/{edit}:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW", "POST")
    if promote:
        with play.edit() as edit:
            actual = play.call(f"/{edit}/tracks/production")
            require(any(release.get("status") == "completed" and release.get("versionCodes") == [str(code)]
                        for release in actual.get("releases", [])), "Production commit could not be verified")
        print(f"Production track verified: version {code}. Review/managed-publishing requirements may still delay availability.")
    else:
        print(f"Internal track and uploaded bundle verified: version {code}, SHA-256 {digest}")


def manifest():
    name, code = release_identity()
    require(os.environ.get("VERSION_CODE") == str(code), "Build number differs from preflight")
    aab = Path("build/app/outputs/bundle/release/app-release.aab")
    digest = hashlib.sha256(aab.read_bytes()).hexdigest()
    values = {"schema_version": 2, "package_name": PACKAGE, "version_name": name, "version_code": code,
              "sha256": digest, "commit": os.environ["GITHUB_SHA"], "run_id": os.environ["GITHUB_RUN_ID"],
              "event": os.environ["GITHUB_EVENT_NAME"], "run_number": int(os.environ["GITHUB_RUN_NUMBER"]),
              "run_attempt": int(os.environ["GITHUB_RUN_ATTEMPT"]), "build_number_base": BUILD_NUMBER_BASE}
    (aab.parent / "release.json").write_text(json.dumps(values, indent=2) + "\n")
    output({"sha256": digest})
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
        summary.write(f"## Release candidate\n- App: `{PACKAGE}`\n- Version: `{name}+{code}`\n"
                      f"- Commit: `{values['commit']}`\n- AAB SHA-256: `{digest}`\n"
                      "- Use Promote Google Play release after testing to request approval for this exact bundle at 100%.\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["preflight", "source-run", "verify-artifact", "gate", "approved-gate", "manifest", "upload-internal", "verify-internal", "promote"])
    args = parser.parse_args()
    if args.command == "preflight":
        preflight()
    elif args.command == "source-run":
        source_run()
    elif args.command == "verify-artifact":
        verify_artifact()
    elif args.command in ("gate", "approved-gate"):
        check_gate(approved=args.command == "approved-gate")
    elif args.command == "manifest":
        manifest()
    else:
        code = int(os.environ["VERSION_CODE"])
        require(code > 0, "Invalid version code")
        play = Play()
        if args.command == "upload-internal":
            upload_internal(play, code, os.environ["AAB_SHA256"])
        else:
            verify_or_promote(play, code, os.environ["AAB_SHA256"], promote=args.command == "promote")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(f"Release stopped: {error}") from None
