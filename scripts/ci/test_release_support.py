"""Offline tests: these never authenticate, sign, upload, or change GitHub/Play."""
import copy
import hashlib
from contextlib import contextmanager
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from android_signing import property_value
import release_support as release


class ReleaseChecksTest(unittest.TestCase):
    def setUp(self):
        self.digest = "a" * 64
        self.internal = {"track": "internal", "releases": [
            {"name": "1.0.20 (21)", "versionCodes": ["21"], "status": "completed",
             "releaseNotes": [{"language": "en-US", "text": "Fixes"}]}]}
        self.bundles = [{"versionCode": 21, "sha256": self.digest}]
        self.environment = {"id": 7, "name": release.PRODUCTION_ENVIRONMENT, "can_admins_bypass": False,
                            "protection_rules": [{"type": "required_reviewers", "reviewers": [{"type": "User"}]}],
                            "deployment_branch_policy": {"custom_branch_policies": True}}
        self.policies = {"branch_policies": [{"name": "main", "type": "branch"}]}

    def test_environment_with_reviewers_and_main_passes(self):
        release.validate_environment(self.environment, self.policies)

    def test_environment_name_alone_is_not_approval(self):
        self.environment["protection_rules"] = []
        with self.assertRaisesRegex(ValueError, "required reviewers"):
            release.validate_environment(self.environment, self.policies)

    def test_empty_reviewers_rejected(self):
        self.environment["protection_rules"][0]["reviewers"] = []
        with self.assertRaises(ValueError):
            release.validate_environment(self.environment, self.policies)

    def test_extra_branch_or_tag_rejected(self):
        for rule in ({"name": "*", "type": "branch"}, {"name": "main", "type": "tag"}):
            with self.subTest(rule=rule), self.assertRaises(ValueError):
                release.validate_environment(self.environment, {"branch_policies": [rule]})

    def test_gate_http_failure_is_not_ignored(self):
        with patch.object(release, "github", side_effect=ValueError("HTTP 403")):
            with self.assertRaisesRegex(ValueError, "403"):
                release.check_gate()

    def test_approval_history_is_required(self):
        with patch.dict(os.environ, {"GITHUB_RUN_ATTEMPT": "1", "GITHUB_RUN_ID": "10"}):
            for history in ([], [{"state": "rejected", "environments": [{"id": 7}]}],
                            [{"state": "approved", "environments": [{"id": 8}]}]):
                with self.subTest(history=history), patch.object(release, "github", side_effect=[self.environment, self.policies, history]):
                    with self.assertRaisesRegex(ValueError, "No production"):
                        release.check_gate(approved=True)

    def test_recorded_environment_approval_passes(self):
        history = [{"state": "approved", "environments": [{"id": 7}]}]
        with patch.dict(os.environ, {"GITHUB_RUN_ATTEMPT": "1", "GITHUB_RUN_ID": "10"}), patch.object(
                release, "github", side_effect=[self.environment, self.policies, history]):
            release.check_gate(approved=True)

    def test_old_run_approval_cannot_authorize_rerun(self):
        with patch.dict(os.environ, {"GITHUB_RUN_ATTEMPT": "2"}), patch.object(
                release, "github", side_effect=[self.environment, self.policies]):
            with self.assertRaisesRegex(ValueError, "reruns are disabled"):
                release.check_gate(approved=True)

    def test_exact_internal_bundle_passes(self):
        self.assertEqual(release.validate_internal(self.internal, self.bundles, 21, self.digest), self.internal["releases"][0])

    def test_wrong_hash_or_version_rejected(self):
        for code, digest in ((22, self.digest), (21, "b" * 64)):
            with self.subTest(code=code), self.assertRaises(ValueError):
                release.validate_internal(self.internal, self.bundles, code, digest)

    def test_draft_and_multi_version_internal_rejected(self):
        for mutation in ({"status": "draft"}, {"versionCodes": ["20", "21"]}):
            candidate = copy.deepcopy(self.internal)
            candidate["releases"][0].update(mutation)
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                release.validate_internal(candidate, self.bundles, 21, self.digest)

    def test_reused_or_lower_version_rejected_across_all_tracks(self):
        for code in (20, 21):
            with self.subTest(code=code), self.assertRaises(ValueError):
                release.validate_new_version([self.internal], [], [], code)
        release.validate_new_version([self.internal], self.bundles, [], 22)

    def test_existing_bundle_or_apk_blocks_upload(self):
        for bundles, apks in (([{"versionCode": 25}], []), ([], [{"versionCode": 25}])):
            with self.subTest(bundles=bundles), self.assertRaises(ValueError):
                release.validate_new_version([], bundles, apks, 24)

    def test_internal_unfinished_release_blocks_upload(self):
        self.internal["releases"][0]["status"] = "draft"
        with self.assertRaisesRegex(ValueError, "unfinished"):
            release.validate_new_version([self.internal], [], [], 22)

    def test_production_promotes_exact_version_and_notes(self):
        desired = release.production_release(self.internal["releases"][0], {"track": "production", "releases": []}, 21)
        self.assertEqual(desired, {"track": "production", "releases": self.internal["releases"]})

    def test_existing_rollouts_and_downgrades_block_promotion(self):
        for status, code in (("inProgress", "20"), ("halted", "20"), ("draft", "20"), ("completed", "21"), ("completed", "22")):
            current = {"track": "production", "releases": [{"status": status, "versionCodes": [code]}]}
            with self.subTest(status=status, code=code), self.assertRaises(ValueError):
                release.production_release(self.internal["releases"][0], current, 21)

    def test_source_identity_and_version(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "android/app").mkdir(parents=True)
            (root / "pubspec.yaml").write_text("version: 1.2.3+42\n")
            (root / "android/app/build.gradle").write_text(f'applicationId = "{release.PACKAGE}"\n')
            self.assertEqual(release.source_version(root), ("1.2.3", 42))
            (root / "android/app/build.gradle").write_text('applicationId = "other.app"\n')
            with self.assertRaisesRegex(ValueError, "application ID"):
                release.source_version(root)

    def test_preflight_rejects_non_main_ref_and_mismatched_version(self):
        environment = {"GITHUB_REPOSITORY": release.REPOSITORY, "GITHUB_REF": "refs/heads/feature",
                       "GITHUB_EVENT_NAME": "workflow_dispatch", "EXPECTED_VERSION": "1.0.20+21"}
        with patch.dict(os.environ, environment), self.assertRaisesRegex(ValueError, "main"):
            release.preflight()
        environment["GITHUB_REF"] = "refs/heads/main"
        with patch.dict(os.environ, environment), patch.object(release, "source_version", return_value=("1.0.19", 20)), self.assertRaisesRegex(ValueError, "confirmation"):
            release.preflight()

    def test_properties_escape_password_characters(self):
        self.assertEqual(property_value(" a=b:c\\d\n"), "\\ a\\=b\\:c\\\\d\\n")
        self.assertEqual(property_value("é😀"), "\\u00e9\\ud83d\\ude00")

    def test_promotion_commits_safely_and_verifies_without_upload(self):
        calls = []
        parent = self

        class FakePlay:
            @contextmanager
            def edit(self):
                yield "edit"

            def call(self, path, method="GET", payload=None):
                calls.append((path, method, payload))
                if path.endswith("/tracks/internal"):
                    return parent.internal
                if path.endswith("/bundles"):
                    return {"bundles": parent.bundles}
                if path.endswith("/tracks/production") and method == "GET":
                    committed = any(":commit?" in call[0] for call in calls)
                    return {"track": "production", "releases": parent.internal["releases"] if committed else []}
                return {}

        release.verify_or_promote(FakePlay(), 21, self.digest, promote=True)
        self.assertIn(("/edit:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW", "POST", None), calls)
        self.assertEqual(sum(method == "PUT" for _, method, _ in calls), 1)
        self.assertFalse(any("upload" in path for path, _, _ in calls))

    def test_changed_internal_hash_causes_no_production_write(self):
        calls = []
        parent = self

        class FakePlay:
            @contextmanager
            def edit(self):
                yield "edit"

            def call(self, path, method="GET", payload=None):
                calls.append(method)
                return parent.internal if path.endswith("/tracks/internal") else {"bundles": parent.bundles}

        with self.assertRaisesRegex(ValueError, "SHA-256"):
            release.verify_or_promote(FakePlay(), 21, "b" * 64, promote=True)
        self.assertEqual(calls, ["GET", "GET"])

    def test_admin_bypass_enabled_or_unknown_rejected(self):
        for value in (True, None):
            self.environment["can_admins_bypass"] = value
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "administrator bypass"):
                release.validate_environment(self.environment, self.policies)

    def test_artifact_matches_source_run_version_and_hash(self):
        data = b"signed candidate"
        candidate = {"package_name": release.PACKAGE, "version_name": "1.0.20", "version_code": 21,
                     "commit": "c" * 40, "run_id": "123", "sha256": hashlib.sha256(data).hexdigest()}
        self.assertEqual(release.validate_manifest(candidate, data, "1.0.20+21", "c" * 40, "123")["version_code"], 21)
        for changed in ({"package_name": "other.app"}, {"version_code": 22}, {"commit": "d" * 40},
                        {"run_id": "124"}, {"sha256": "b" * 64}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                release.validate_manifest({**candidate, **changed}, data, "1.0.20+21", "c" * 40, "123")

    def test_source_run_requires_successful_main_release_workflow(self):
        run = {"repository": {"full_name": release.REPOSITORY}, "head_branch": "main", "event": "workflow_dispatch",
               "path": ".github/workflows/google-play-release.yml", "status": "completed", "conclusion": "success",
               "run_attempt": 1, "head_sha": "c" * 40}
        artifacts = {"artifacts": [{"id": 99, "name": "play-aab-123-1", "expired": False}]}
        environment = {"GITHUB_REPOSITORY": release.REPOSITORY, "GITHUB_REF": "refs/heads/main",
                       "GITHUB_EVENT_NAME": "workflow_dispatch", "INTERNAL_RUN_ID": "123"}
        with patch.dict(os.environ, environment), patch.object(release, "check_gate"), patch.object(release, "output") as output:
            with patch.object(release, "github", side_effect=[run, artifacts]):
                release.source_run()
            output.assert_called_once_with({"artifact_id": 99, "source_commit": "c" * 40})
            for changed in ({"head_branch": "feature"}, {"event": "pull_request"}, {"conclusion": "failure"},
                            {"path": ".github/workflows/other.yml"}, {"repository": {"full_name": "other/repo"}}):
                with self.subTest(changed=changed), patch.object(release, "github", return_value={**run, **changed}), self.assertRaises(ValueError):
                    release.source_run()

    def test_upload_response_mismatch_never_updates_track_or_commits(self):
        data = b"signed candidate"
        digest = hashlib.sha256(data).hexdigest()
        for uploaded in ({"versionCode": 22, "sha256": digest}, {"versionCode": 21, "sha256": "b" * 64}):
            calls = []

            class FakePlay:
                token = "fake-not-a-credential"

                @contextmanager
                def edit(self):
                    yield "edit"

                def call(self, path, method="GET", payload=None):
                    calls.append((path, method))
                    return {}

            with self.subTest(uploaded=uploaded), patch.object(Path, "read_bytes", return_value=data), patch.object(
                    release, "request_json", return_value=uploaded), self.assertRaisesRegex(ValueError, "Uploaded bundle"):
                release.upload_internal(FakePlay(), 21, digest)
            self.assertTrue(all(method == "GET" for _, method in calls))

    def test_reused_version_does_not_upload_media(self):
        data = b"signed candidate"
        parent = self

        class FakePlay:
            @contextmanager
            def edit(self):
                yield "edit"

            def call(self, path, method="GET", payload=None):
                return {"tracks": [parent.internal]} if path.endswith("/tracks") else {}

        with patch.object(Path, "read_bytes", return_value=data), patch.object(release, "request_json") as upload:
            with self.assertRaisesRegex(ValueError, "Version code"):
                release.upload_internal(FakePlay(), 21, hashlib.sha256(data).hexdigest())
            upload.assert_not_called()


if __name__ == "__main__":
    unittest.main()
