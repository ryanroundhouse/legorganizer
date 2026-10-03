"""Offline tests: these never authenticate, sign, upload, or change GitHub/Play."""
import copy
import hashlib
import json
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
                       "GITHUB_EVENT_NAME": "workflow_dispatch", "EXPECTED_VERSION_NAME": "1.0.20", "GITHUB_RUN_NUMBER": "2"}
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
        self.assertEqual(release.validate_manifest(candidate, data, "c" * 40, "123", "workflow_dispatch", 1, 1)["version"], "1.0.20+21")
        for changed in ({"package_name": "other.app"}, {"version_code": 0}, {"version_name": "invalid"}, {"commit": "d" * 40},
                        {"run_id": "124"}, {"sha256": "b" * 64}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                release.validate_manifest({**candidate, **changed}, data, "c" * 40, "123", "workflow_dispatch", 1, 1)

    def test_source_run_requires_successful_main_release_workflow(self):
        run = {"id": 123, "repository": {"full_name": release.REPOSITORY}, "head_branch": "main", "event": "workflow_dispatch",
               "path": ".github/workflows/google-play-release.yml", "status": "completed", "conclusion": "success",
               "run_attempt": 1, "run_number": 1, "head_sha": "c" * 40}
        artifacts = {"total_count": 1, "artifacts": [{"id": 99, "name": "play-aab-123-1", "expired": False}]}
        runs = {"total_count": 1, "workflow_runs": [run]}
        environment = {"GITHUB_REPOSITORY": release.REPOSITORY, "GITHUB_REF": "refs/heads/main",
                       "GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_RUN_ATTEMPT": "1"}
        with patch.dict(os.environ, environment), patch.object(release, "check_gate"), patch.object(release, "output") as output:
            with patch.object(release, "github", side_effect=[runs, run, artifacts, run]):
                release.source_run()
            output.assert_called_once_with({"run_id": "123", "artifact_id": 99, "source_commit": "c" * 40,
                                           "source_event": "workflow_dispatch", "source_run_number": 1, "source_run_attempt": 1})
            for changed in ({"head_branch": "feature"}, {"event": "pull_request"}, {"conclusion": "failure"},
                            {"path": ".github/workflows/other.yml"}, {"repository": {"full_name": "other/repo"}}):
                with self.subTest(changed=changed), patch.object(release, "github", return_value={"total_count": 1, "workflow_runs": [{**run, **changed}]}), self.assertRaises(ValueError):
                    release.source_run()

    def test_push_source_uses_latest_attempt_and_exact_run_counters(self):
        run = {"id": 123, "repository": {"full_name": release.REPOSITORY}, "head_branch": "main", "event": "push",
               "path": ".github/workflows/google-play-release.yml", "status": "completed", "conclusion": "success",
               "run_attempt": 4, "run_number": 2, "head_sha": "c" * 40}
        artifacts = {"total_count": 2, "artifacts": [{"id": 98, "name": "play-aab-123-3", "expired": False},
                                  {"id": 99, "name": "play-aab-123-4", "expired": False}]}
        environment = {"GITHUB_REPOSITORY": release.REPOSITORY, "GITHUB_REF": "refs/heads/main",
                       "GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_RUN_ATTEMPT": "1"}
        with patch.dict(os.environ, environment), patch.object(release, "check_gate"), patch.object(release, "output") as output:
            with patch.object(release, "github", side_effect=[{"total_count": 1, "workflow_runs": [run]}, run, artifacts, run]):
                release.source_run()
            output.assert_called_once_with({"run_id": "123", "artifact_id": 99, "source_commit": "c" * 40,
                                           "source_event": "push", "source_run_number": 2, "source_run_attempt": 4})
            for changed in ({"run_number": True}, {"run_number": 0}, {"run_attempt": 0}):
                with self.subTest(changed=changed), patch.object(release, "github", return_value={"total_count": 1, "workflow_runs": [{**run, **changed}]}), self.assertRaises(ValueError):
                    release.source_run()

    def test_push_cannot_start_production_promotion(self):
        with patch.dict(os.environ, {"GITHUB_REPOSITORY": release.REPOSITORY, "GITHUB_REF": "refs/heads/main",
                                    "GITHUB_EVENT_NAME": "push"}), patch.object(release, "check_gate") as gate:
            with self.assertRaisesRegex(ValueError, "Manual dispatch"):
                release.source_run()
            gate.assert_not_called()

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

    def test_older_candidate_replaced_on_internal_cannot_promote(self):
        newer = copy.deepcopy(self.internal)
        newer["releases"][0]["versionCodes"] = ["22"]
        calls = []
        bundles = self.bundles

        class FakePlay:
            @contextmanager
            def edit(self):
                yield "edit"

            def call(self, path, method="GET", payload=None):
                calls.append(method)
                return newer if path.endswith("/tracks/internal") else {"bundles": bundles}

        with self.assertRaisesRegex(ValueError, "completed internal-testing"):
            release.verify_or_promote(FakePlay(), 21, self.digest, promote=True)
        self.assertEqual(calls, ["GET", "GET"])

    def test_additional_internal_release_blocks_promotion_before_writes(self):
        for status in ("completed", "draft", "inProgress"):
            mixed = copy.deepcopy(self.internal)
            mixed["releases"].append({"status": status, "versionCodes": ["22"]})
            calls = []
            bundles = self.bundles

            class FakePlay:
                @contextmanager
                def edit(self):
                    yield "edit"

                def call(self, path, method="GET", payload=None):
                    calls.append(method)
                    return mixed if path.endswith("/tracks/internal") else {"bundles": bundles}

            with self.subTest(status=status), self.assertRaisesRegex(ValueError, "sole completed"):
                release.verify_or_promote(FakePlay(), 21, self.digest, promote=True)
            self.assertEqual(calls, ["GET", "GET"])


class LatestCandidateTest(unittest.TestCase):
    def setUp(self):
        self.environment = {"GITHUB_REPOSITORY": release.REPOSITORY, "GITHUB_REF": "refs/heads/main",
                            "GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_RUN_ATTEMPT": "1"}
        self.old = self.make_run(100, 1, run_attempt=4, updated_at="2030-01-01T00:00:00Z")
        self.new = self.make_run(200, 2, updated_at="2026-10-03T00:00:00Z")
        self.artifact = {"id": 99, "name": "play-aab-200-1", "expired": False}

    @staticmethod
    def make_run(run_id, number, **changes):
        return {"id": run_id, "repository": {"full_name": release.REPOSITORY}, "head_branch": "main",
                "event": "push", "path": release.RELEASE_WORKFLOW, "status": "completed", "conclusion": "success",
                "run_number": number, "run_attempt": 1, "head_sha": "c" * 40, **changes}

    @staticmethod
    def page(key, items, total=None):
        return {"total_count": len(items) if total is None else total, key: items}

    def test_highest_successful_number_wins_not_timestamp_or_api_order(self):
        failed = self.make_run(300, 3, conclusion="failure")
        pending = self.make_run(400, 4, status="in_progress", conclusion=None)
        for runs in ([self.old, self.new, failed, pending], [pending, failed, self.new, self.old]):
            self.assertEqual(release.latest_source_run(runs), self.new)

    def test_untrusted_sources_are_ineligible(self):
        for changed in ({"event": "pull_request"}, {"head_branch": "feature"}, {"path": "other.yml"},
                        {"repository": {"full_name": "other/repo"}}, {"status": "queued"}, {"conclusion": "cancelled"}):
            with self.subTest(changed=changed):
                self.assertEqual(release.latest_source_run([self.old, {**self.new, **changed}]), self.old)
        with self.assertRaisesRegex(ValueError, "No successful"):
            release.latest_source_run([])

    def test_malformed_or_ambiguous_latest_number_stops(self):
        for changes in ({"run_number": True}, {"run_number": "2"}, {"run_attempt": 0}, {"head_sha": None}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                release.latest_source_run([self.old, {**self.new, **changes}])
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            release.latest_source_run([self.new, {**self.new, "id": 201}])

    def test_full_unfiltered_pagination_including_more_than_1000_runs(self):
        runs = [self.make_run(index, index) for index in range(1, 1002)]
        pages = [self.page("workflow_runs", runs[start:start + 100], len(runs)) for start in range(0, len(runs), 100)]
        with patch.object(release, "github", side_effect=pages) as github:
            received = release.github_collection("actions/workflows/google-play-release.yml/runs", "workflow_runs")
        self.assertEqual(release.latest_source_run(received)["id"], 1001)
        self.assertEqual(github.call_count, 11)
        self.assertTrue(all("?per_page=100&page=" in call.args[0] for call in github.call_args_list))
        self.assertFalse(any("branch=" in call.args[0] or "status=" in call.args[0] for call in github.call_args_list))

    def test_truncated_duplicate_or_changing_pagination_stops(self):
        bad_pages = [
            [self.page("workflow_runs", [self.old], 2), self.page("workflow_runs", [], 2)],
            [self.page("workflow_runs", [self.old], 2), self.page("workflow_runs", [self.old], 2)],
            [self.page("workflow_runs", [self.old], 2), self.page("workflow_runs", [self.new], 3)],
            [self.page("workflow_runs", [self.old], 0)],
            [{"total_count": True, "workflow_runs": []}],
            [{"total_count": 1, "workflow_runs": {}}],
            [self.page("workflow_runs", [{"id": "100"}])],
        ]
        for pages in bad_pages:
            with self.subTest(pages=pages), patch.object(release, "github", side_effect=pages), self.assertRaises(ValueError):
                release.github_collection("runs", "workflow_runs")

    def test_source_pins_latest_run_and_finds_artifact_on_later_page(self):
        artifacts = [{"id": index, "name": f"unrelated-{index}", "expired": False} for index in range(1, 101)]
        chosen = {**self.artifact, "id": 101}
        responses = [self.page("workflow_runs", [self.old], 2), self.page("workflow_runs", [self.new], 2), self.new,
                     self.page("artifacts", artifacts, 101), self.page("artifacts", [chosen], 101), self.new]
        with patch.dict(os.environ, self.environment), patch.object(release, "check_gate"), patch.object(
                release, "github", side_effect=responses), patch.object(release, "output") as output:
            release.source_run()
        output.assert_called_once_with({"run_id": "200", "artifact_id": 101, "source_commit": "c" * 40,
                                       "source_event": "push", "source_run_number": 2, "source_run_attempt": 1})

    def test_missing_expired_duplicate_latest_artifact_never_falls_back(self):
        for artifacts in ([], [{**self.artifact, "expired": True}], [{**self.artifact, "name": "play-aab-200-2"}],
                          [self.artifact, {**self.artifact, "id": 98}], [{key: value for key, value in self.artifact.items() if key != "expired"}]):
            responses = [self.page("workflow_runs", [self.old, self.new]), self.new, self.page("artifacts", artifacts)]
            with self.subTest(artifacts=artifacts), patch.dict(os.environ, self.environment), patch.object(release, "check_gate"), patch.object(
                    release, "github", side_effect=responses) as github, patch.object(release, "output") as output:
                with self.assertRaisesRegex(ValueError, "no older fallback"):
                    release.source_run()
                output.assert_not_called()
                self.assertFalse(any("actions/runs/100" in call.args[0] for call in github.call_args_list))

    def test_run_retry_or_identity_race_stops_without_outputs(self):
        for changes in ({"run_attempt": 2}, {"head_sha": "d" * 40}, {"run_number": 3},
                        {"status": "queued", "conclusion": None}, {"conclusion": "failure"}):
            changed = {**self.new, **changes}
            for responses in ([self.page("workflow_runs", [self.new]), changed],
                              [self.page("workflow_runs", [self.new]), self.new, self.page("artifacts", [self.artifact]), changed]):
                with self.subTest(changes=changes), patch.dict(os.environ, self.environment), patch.object(release, "check_gate"), patch.object(
                        release, "github", side_effect=responses), patch.object(release, "output") as output, self.assertRaises(ValueError):
                    release.source_run()
                output.assert_not_called()

    def test_production_rerun_cannot_reselect_candidate(self):
        with patch.dict(os.environ, {**self.environment, "GITHUB_RUN_ATTEMPT": "2"}), patch.object(release, "github") as github:
            with self.assertRaisesRegex(ValueError, "reruns are disabled"):
                release.source_run()
            github.assert_not_called()


class AutomaticNumberingTest(unittest.TestCase):
    def setUp(self):
        self.environment = {"GITHUB_REPOSITORY": release.REPOSITORY, "GITHUB_REF": "refs/heads/main",
                            "GITHUB_EVENT_NAME": "push", "GITHUB_RUN_NUMBER": "2", "GITHUB_RUN_ATTEMPT": "1",
                            "GITHUB_RUN_ID": "123", "GITHUB_SHA": "c" * 40, "VERSION_CODE": "1002"}
        self.data = b"signed automatic candidate"
        self.candidate = {"schema_version": 2, "package_name": release.PACKAGE, "version_name": "1.0.20",
                          "version_code": 1002, "commit": "c" * 40, "run_id": "123", "event": "push",
                          "run_number": 2, "run_attempt": 1, "build_number_base": 1000,
                          "sha256": hashlib.sha256(self.data).hexdigest()}

    def validate(self, candidate=None, **changes):
        return release.validate_manifest(candidate or {**self.candidate, **changes}, self.data,
                                         "c" * 40, "123", "push", 2, 1)

    def test_new_runs_increase_and_retries_keep_same_number(self):
        self.assertEqual(release.automatic_version_code("2"), 1002)
        self.assertEqual(release.automatic_version_code("3"), 1003)
        for attempt in ("1", "2", "4"):
            with patch.dict(os.environ, {**self.environment, "GITHUB_RUN_ATTEMPT": attempt}), patch.object(
                    release, "source_version", return_value=("1.0.20", 21)):
                self.assertEqual(release.release_identity(), ("1.0.20", 1002))

    def test_invalid_and_overflow_run_numbers_rejected(self):
        for number in ("", "0", "-1", "1.5", "02", "2\n", " 2", True, None, "2100000000"):
            with self.subTest(number=number), self.assertRaises(ValueError):
                release.automatic_version_code(number)
        self.assertEqual(release.automatic_version_code(str(release.MAX_VERSION_CODE - release.BUILD_NUMBER_BASE)),
                         release.MAX_VERSION_CODE)

    def test_push_preflight_needs_no_manual_input(self):
        with patch.dict(os.environ, self.environment), patch.object(release, "source_version", return_value=("1.0.20", 21)), patch.object(
                release, "output") as output:
            release.preflight()
            output.assert_called_once_with({"version_name": "1.0.20", "version_code": 1002})

    def test_manual_preflight_confirms_name_but_automates_number(self):
        with patch.dict(os.environ, {**self.environment, "GITHUB_EVENT_NAME": "workflow_dispatch",
                                    "EXPECTED_VERSION_NAME": "1.0.20"}), patch.object(
                release, "source_version", return_value=("1.0.20", 21)), patch.object(release, "output") as output:
            release.preflight()
            output.assert_called_once_with({"version_name": "1.0.20", "version_code": 1002})

    def test_other_events_refs_and_repositories_cannot_release(self):
        for changed in ({"GITHUB_EVENT_NAME": "pull_request"}, {"GITHUB_EVENT_NAME": "pull_request_target"},
                        {"GITHUB_EVENT_NAME": "workflow_run"}, {"GITHUB_REF": "refs/heads/feature"},
                        {"GITHUB_REF": "refs/tags/main"}, {"GITHUB_REPOSITORY": "other/legorganizer"}):
            with self.subTest(changed=changed), patch.dict(os.environ, {**self.environment, **changed}), self.assertRaises(ValueError):
                release.preflight()

    def test_manifest_records_effective_version_and_attempt(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {
                **self.environment, "GITHUB_STEP_SUMMARY": str(Path(folder) / "summary")}), patch.object(
                release, "source_version", return_value=("1.0.20", 21)), patch.object(Path, "read_bytes", return_value=self.data), patch.object(
                Path, "write_text") as write, patch.object(release, "output"):
            release.manifest()
            self.assertEqual(json.loads(write.call_args.args[0]), self.candidate)
            self.assertIn("1.0.20+1002", (Path(folder) / "summary").read_text())

    def test_manifest_rejects_changed_preflight_number(self):
        with patch.dict(os.environ, {**self.environment, "VERSION_CODE": "21"}), patch.object(
                release, "source_version", return_value=("1.0.20", 21)), self.assertRaisesRegex(ValueError, "preflight"):
            release.manifest()

    def test_automatic_manifest_checks_effective_version(self):
        self.assertEqual(self.validate()["version_code"], 1002)
        for changed in ({"version_code": 21}, {"run_number": 3}, {"run_number": True}, {"run_attempt": 2},
                        {"event": "workflow_dispatch"}, {"build_number_base": 999}, {"build_number_base": True},
                        {"schema_version": 3}, {"schema_version": 2.0}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                self.validate(**changed)

    def test_push_source_cannot_use_legacy_manifest(self):
        legacy = {key: value for key, value in self.candidate.items() if key != "schema_version"}
        with self.assertRaisesRegex(ValueError, "versioned release manifest"):
            self.validate(legacy)

    def test_current_base_change_does_not_rewrite_old_candidate(self):
        with patch.object(release, "BUILD_NUMBER_BASE", 2000):
            self.assertEqual(self.validate()["version_code"], 1002)

    def test_no_input_artifact_verification_pins_version_and_approval_summary(self):
        with tempfile.TemporaryDirectory() as folder:
            summary = Path(folder) / "summary"
            env = {"INTERNAL_RUN_ID": "123", "SOURCE_COMMIT": "c" * 40, "SOURCE_EVENT": "push",
                   "SOURCE_RUN_NUMBER": "2", "SOURCE_RUN_ATTEMPT": "1", "SOURCE_ARTIFACT_ID": "99",
                   "GITHUB_STEP_SUMMARY": str(summary)}
            with patch.dict(os.environ, env, clear=True), patch.object(Path, "read_text", return_value=json.dumps(self.candidate)), patch.object(
                    Path, "read_bytes", return_value=self.data), patch.object(release, "output") as output:
                release.verify_artifact()
                output.assert_called_once_with({"version": "1.0.20+1002", "version_code": 1002,
                                                "sha256": self.candidate["sha256"]})
            text = summary.read_text()
            for expected in ("1.0.20+1002", "100% production", "artifact ID: `99`", "candidate is pinned", self.candidate["sha256"]):
                self.assertIn(expected, text)


if __name__ == "__main__":
    unittest.main()
