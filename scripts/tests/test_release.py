"""Release command contract. GitHub is replaced only at the external CLI boundary."""
import os
import json
import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/release.py'


class ReleaseTests(unittest.TestCase):
    def run_release(self, *args, env=None):
        return subprocess.run(['python3', str(SCRIPT), *args], cwd=ROOT,
                              env=env, capture_output=True, text=True)

    def github_fixture(self, directory, responses):
        command = Path(directory) / 'gh'
        command.write_text("""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
responses = json.loads(Path(os.environ['TEST_RESPONSES']).read_text())
key = ' '.join(sys.argv[1:])
if key not in responses:
    sys.exit('unexpected GitHub request: ' + key)
print(json.dumps(responses[key]))
""")
        command.chmod(0o755)
        data = Path(directory) / 'responses.json'
        data.write_text(json.dumps(responses))
        return dict(os.environ, PATH=f'{directory}:' + os.environ['PATH'],
                    TEST_RESPONSES=str(data), GITHUB_REPOSITORY='kuan0808/MonsterDeleter',
                    GITHUB_REF='refs/heads/main', GITHUB_EVENT_NAME='workflow_dispatch', GITHUB_SHA='a' * 40)

    def test_source_run_rejects_failed_or_untrusted_inputs(self):
        sha = 'a' * 40
        run = dict(id=123, head_sha=sha, head_branch='main', event='workflow_dispatch',
                   path='.github/workflows/release-candidate.yml', status='completed',
                   conclusion='success', repository={'full_name': 'kuan0808/MonsterDeleter'},
                   head_repository={'full_name': 'kuan0808/MonsterDeleter'})
        for delta in ({'conclusion': 'failure'}, {'head_sha': 'b' * 40},
                      {'event': 'pull_request'}, {'head_branch': 'untrusted'},
                      {'path': '.github/workflows/ci.yml'}, {'status': 'in_progress'},
                      {'head_repository': {'full_name': 'someone/fork'}}):
            with self.subTest(delta=delta), tempfile.TemporaryDirectory() as directory:
                env = self.github_fixture(directory, {
                    'api repos/kuan0808/MonsterDeleter/actions/runs/123': run | delta})
                result = self.run_release('source-run', '123', sha, env=env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('trusted successful candidate', result.stderr)

    def candidate_fixture(self, directory):
        candidate = Path(directory) / 'candidate'
        candidate.mkdir()
        stem = 'MonsterDeleter-0.4.0-build7-macos15-universal'
        names = [stem + '.zip', stem + '.dmg', 'INSTALL.txt']
        for name, data in zip(names, (b'zip bytes', b'dmg bytes', b'install steps')):
            (candidate / name).write_bytes(data)
        hashes = {name: hashlib.sha256((candidate / name).read_bytes()).hexdigest() for name in names}
        (candidate / 'SHA256SUMS.txt').write_text(''.join(f'{hashes[name]}  {name}\n' for name in names))
        hashes['SHA256SUMS.txt'] = hashlib.sha256((candidate / 'SHA256SUMS.txt').read_bytes()).hexdigest()
        body = 'Reviewed release notes\n'
        (candidate / 'release-notes.md').write_text(body)
        manifest = dict(tag='v0.4.0-build7', version='0.4.0', build='7', source_commit='a' * 40,
                        source_run='123', signing='developer-id-notarized', assets=hashes,
                        body_sha256=hashlib.sha256(body.encode()).hexdigest())
        (candidate / 'candidate.json').write_text(json.dumps(manifest))
        return candidate, manifest

    def publisher_fixture(self, directory, candidate):
        command = Path(directory) / 'gh'
        command.write_text("""#!/usr/bin/env python3
import hashlib, json, os, sys
from pathlib import Path
path = Path(os.environ['TEST_STATE'])
state = json.loads(path.read_text())
args = sys.argv[1:]
state['calls'].append(args)
result = None
if args[0] == 'api':
    endpoint = args[1]
    if endpoint == 'repos/kuan0808/MonsterDeleter':
        result = {'private': False, 'default_branch': 'main'}
    elif '/releases?' in endpoint:
        result = [[state['release']] if state['release'] and not state.get('stale_list') else []]
    elif endpoint == 'repos/kuan0808/MonsterDeleter/releases' and '--method' in args:
        assert args[args.index('--method') + 1] == 'POST'
        assert args[args.index('--input') + 1] == '-'
        state['release'] = dict(json.load(sys.stdin), id=10)
        result = state.get('creation_response', state['release'])
    elif '/commits/' in endpoint:
        result = {'sha': 'a' * 40}
    elif '/matching-refs/' in endpoint:
        result = state.get('refs', [])
    elif endpoint.endswith('/git/refs'):
        state['refs'] = [{'ref': 'refs/tags/v0.4.0-build7', 'object': {'sha': 'a' * 40, 'type': 'commit'}}]
    elif '/assets?' in endpoint:
        assert endpoint == f"repos/kuan0808/MonsterDeleter/releases/{state['release']['id']}/assets?per_page=100"
        result = state['assets']
    elif '/releases/tags/' in endpoint:
        sys.exit('tag lookup is for published releases; list drafts instead')
    elif '/releases/' in endpoint:
        assert endpoint == f"repos/kuan0808/MonsterDeleter/releases/{state['release']['id']}"
        result = state['release']
else:
    action = args[1]
    if action == 'upload':
        if state.get('fail_upload') and len(state['assets']) >= 1:
            state['fail_upload'] = False
            path.write_text(json.dumps(state))
            sys.exit('simulated interrupted upload')
        asset = Path(args[3])
        state['assets'].append(dict(name=asset.name, state='uploaded', size=asset.stat().st_size,
            digest='sha256:' + hashlib.sha256(asset.read_bytes()).hexdigest()))
        if state.get('move_tag_after_upload'):
            state['refs'] = [{'ref': 'refs/tags/v0.4.0-build7', 'object': {'sha': 'c' * 40, 'type': 'commit'}}]
    elif action == 'edit':
        state['release']['draft'] = False
    else:
        sys.exit('unexpected mutation: ' + str(args))
path.write_text(json.dumps(state))
print(json.dumps(result))
""")
        command.chmod(0o755)
        state = Path(directory) / 'state.json'
        state.write_text(json.dumps(dict(release=None, assets=[], calls=[])))
        env = dict(os.environ, PATH=f'{directory}:' + os.environ['PATH'], TEST_STATE=str(state),
                   GITHUB_REPOSITORY='kuan0808/MonsterDeleter', GITHUB_REF='refs/heads/main',
                   GITHUB_EVENT_NAME='workflow_dispatch', GITHUB_SHA='a' * 40)
        return env, state

    def test_new_draft_publishes_exact_assets_when_release_list_is_stale(self):
        with tempfile.TemporaryDirectory() as directory:
            candidate, manifest = self.candidate_fixture(directory)
            env, state_path = self.publisher_fixture(directory, candidate)
            state = json.loads(state_path.read_text())
            state['stale_list'] = True
            state_path.write_text(json.dumps(state))
            result = self.run_release('publish', str(candidate), manifest['tag'], 'a' * 40, '123', env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            state = json.loads(state_path.read_text())
            self.assertEqual(state['release'], dict(id=10, draft=False, prerelease=False,
                tag_name='v0.4.0-build7', target_commitish='a' * 40,
                name='MonsterDeleter 0.4.0 (build 7)', body='Reviewed release notes\n'))
            self.assertEqual(len(state['assets']), 4)
            self.assertEqual({asset['name']: (asset['state'], asset['size'], asset['digest'])
                              for asset in state['assets']},
                             {name: ('uploaded', (candidate / name).stat().st_size, 'sha256:' + digest)
                              for name, digest in manifest['assets'].items()})
            self.assertEqual(state['refs'], [{'ref': 'refs/tags/v0.4.0-build7',
                                              'object': {'sha': 'a' * 40, 'type': 'commit'}}])

    def test_mismatched_creation_response_stops_before_uploads(self):
        release = dict(id=10, draft=True, prerelease=False, tag_name='v0.4.0-build7',
                       target_commitish='a' * 40, name='MonsterDeleter 0.4.0 (build 7)',
                       body='Reviewed release notes\n')
        responses = [release | delta for delta in (
            {'id': 0}, {'id': -1}, {'id': True}, {'id': '10'}, {'id': 10.5},
            {'draft': False}, {'draft': 'true'}, {'prerelease': True}, {'prerelease': 0},
            {'tag_name': 'v0.4.0-build8'}, {'target_commitish': 'b' * 40},
            {'name': 'Other release'}, {'body': 'Other notes'})]
        responses += [{key: value for key, value in release.items() if key != missing}
                      for missing in release]
        responses += [None, []]
        for response in responses:
            with self.subTest(response=response), tempfile.TemporaryDirectory() as directory:
                candidate, manifest = self.candidate_fixture(directory)
                env, state_path = self.publisher_fixture(directory, candidate)
                state = json.loads(state_path.read_text())
                state['creation_response'] = response
                state_path.write_text(json.dumps(state))
                result = self.run_release('publish', str(candidate), manifest['tag'], 'a' * 40, '123', env=env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('creation response', result.stderr)
                state = json.loads(state_path.read_text())
                self.assertTrue(state['release']['draft'])
                self.assertEqual(state['assets'], [])
                self.assertEqual(state.get('refs', []), [])
                self.assertFalse(any(call[0] == 'release' for call in state['calls']))

    def test_interrupted_upload_retries_draft_then_rejects_published_version(self):
        with tempfile.TemporaryDirectory() as directory:
            candidate, manifest = self.candidate_fixture(directory)
            env, state_path = self.publisher_fixture(directory, candidate)
            state = json.loads(state_path.read_text())
            state['fail_upload'] = True
            state_path.write_text(json.dumps(state))
            args = ('publish', str(candidate), manifest['tag'], 'a' * 40, '123')
            first = self.run_release(*args, env=env)
            self.assertNotEqual(first.returncode, 0)
            self.assertTrue(json.loads(state_path.read_text())['release']['draft'])
            self.assertEqual(len(json.loads(state_path.read_text())['assets']), 1)
            retry = self.run_release(*args, env=env)
            self.assertEqual(retry.returncode, 0, retry.stderr)
            state = json.loads(state_path.read_text())
            self.assertFalse(state['release']['draft'])
            self.assertEqual({asset['name'] for asset in state['assets']}, set(manifest['assets']))
            third = self.run_release(*args, env=env)
            self.assertNotEqual(third.returncode, 0)
            self.assertIn('already published', third.stderr)
            self.assertEqual(sum(call[:2] == ['api', 'repos/kuan0808/MonsterDeleter/releases']
                                 and '--method' in call and call[call.index('--method') + 1] == 'POST'
                                 for call in state['calls']), 1)

    def test_corrupt_or_extra_candidate_files_cannot_publish(self):
        for mutation in ('corrupt', 'extra', 'adhoc'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                candidate, manifest = self.candidate_fixture(directory)
                if mutation == 'corrupt':
                    (candidate / 'INSTALL.txt').write_text('changed')
                elif mutation == 'extra':
                    (candidate / 'private-report.txt').write_text('private')
                else:
                    manifest['signing'] = 'ad-hoc'
                    (candidate / 'candidate.json').write_text(json.dumps(manifest))
                env, state_path = self.publisher_fixture(directory, candidate)
                result = self.run_release('publish', str(candidate), manifest['tag'], 'a' * 40, '123', env=env)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(json.loads(state_path.read_text())['calls'], [])

    def test_source_run_reuses_one_producer_but_rejects_ambiguous_rebuilds(self):
        sha = 'a' * 40
        run = dict(id=123, head_sha=sha, head_branch='main', event='workflow_dispatch',
                   path='.github/workflows/release-candidate.yml', status='completed',
                   conclusion='success', run_attempt=2,
                   repository={'full_name': 'kuan0808/MonsterDeleter'},
                   head_repository={'full_name': 'kuan0808/MonsterDeleter'})
        artifact = dict(id=456, name='release-candidate-123-1', expired=False)
        for artifacts, succeeds in (([artifact], True), ([], False),
                                    ([artifact, artifact | {'id': 789, 'name': 'release-candidate-123-2'}], False),
                                    ([artifact | {'expired': True}], False)):
            with self.subTest(artifacts=artifacts), tempfile.TemporaryDirectory() as directory:
                env = self.github_fixture(directory, {
                    'api repos/kuan0808/MonsterDeleter/actions/runs/123': run,
                    f'api repos/kuan0808/MonsterDeleter/compare/{sha}...main': {'status': 'identical'},
                    'api repos/kuan0808/MonsterDeleter/actions/runs/123/artifacts?per_page=100':
                        {'total_count': len(artifacts), 'artifacts': artifacts}})
                result = self.run_release('source-run', '123', sha, env=env)
                self.assertEqual(result.returncode == 0, succeeds, result.stderr)
                if succeeds:
                    self.assertEqual(result.stdout.strip(), '456')

    def test_existing_tag_or_mismatched_draft_never_changes(self):
        for conflict in ('tag', 'body', 'asset'):
            with self.subTest(conflict=conflict), tempfile.TemporaryDirectory() as directory:
                candidate, manifest = self.candidate_fixture(directory)
                env, state_path = self.publisher_fixture(directory, candidate)
                state = json.loads(state_path.read_text())
                if conflict == 'tag':
                    state['refs'] = [{'ref': 'refs/tags/v0.4.0-build7',
                                      'object': {'sha': 'c' * 40, 'type': 'commit'}}]
                else:
                    state['release'] = dict(id=10, draft=True, prerelease=False, tag_name=manifest['tag'],
                        target_commitish='a' * 40, name='MonsterDeleter 0.4.0 (build 7)',
                        body='other notes' if conflict == 'body' else 'Reviewed release notes\n')
                    if conflict == 'asset':
                        state['assets'] = [{'name': 'INSTALL.txt', 'size': 13, 'state': 'uploaded',
                                            'digest': 'sha256:' + '0' * 64}]
                state_path.write_text(json.dumps(state))
                result = self.run_release('publish', str(candidate), manifest['tag'], 'a' * 40, '123', env=env)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(call[0] == 'release' for call in json.loads(state_path.read_text())['calls']))

    def test_tag_changed_during_upload_cannot_publish(self):
        with tempfile.TemporaryDirectory() as directory:
            candidate, manifest = self.candidate_fixture(directory)
            env, state_path = self.publisher_fixture(directory, candidate)
            state = json.loads(state_path.read_text())
            state['move_tag_after_upload'] = True
            state_path.write_text(json.dumps(state))
            result = self.run_release('publish', str(candidate), manifest['tag'], 'a' * 40, '123', env=env)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(json.loads(state_path.read_text())['release']['draft'])

    def test_publish_requires_the_reviewed_commit_to_be_the_dispatch_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            candidate, manifest = self.candidate_fixture(directory)
            env, state_path = self.publisher_fixture(directory, candidate)
            env['GITHUB_SHA'] = 'b' * 40
            result = self.run_release('publish', str(candidate), manifest['tag'], 'a' * 40, '123', env=env)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('dispatch commit', result.stderr)
            self.assertEqual(json.loads(state_path.read_text())['calls'], [])

    def test_missing_credentials_stop_before_keychain_changes(self):
        env = {'PATH': os.environ['PATH']}
        result = subprocess.run(['/bin/sh', 'scripts/release-signing.sh', 'check'],
                                cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing release credentials:', result.stderr)
        self.assertIn('DEVELOPER_ID_P12_BASE64', result.stderr)

    def test_required_notarization_cannot_succeed_without_profile(self):
        result = subprocess.run(['/bin/sh', 'scripts/notarize.sh'], cwd=ROOT,
                                env={'PATH': os.environ['PATH'], 'NOTARY_REQUIRED': '1'},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('NOTARY_PROFILE', result.stdout + result.stderr)

    def test_version_must_match_plist(self):
        result = self.run_release('version', 'v9.9.9-build1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('does not match', result.stderr)


if __name__ == '__main__':
    unittest.main()
