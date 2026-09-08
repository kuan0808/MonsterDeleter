#!/usr/bin/env python3
"""Versioned release commands; CI uses the GitHub CLI bundled with hosted runners."""
import argparse
import hashlib
import shutil
import json
import os
import subprocess
import plistlib
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'kuan0808/MonsterDeleter'


def version(tag, plist=None):
    if plist is None:
        plist = plistlib.loads((ROOT / 'Packaging/Info.plist').read_bytes())
    number, build = plist['CFBundleShortVersionString'], plist['CFBundleVersion']
    expected = f'v{number}-build{build}'
    if not re.fullmatch(r'v\d+\.\d+\.\d+-build[1-9]\d*', tag) or tag != expected:
        raise ValueError(f'tag {tag!r} does not match app version/build {expected}')
    return number, build


def github(*args, input=None):
    return subprocess.check_output(['gh', *args], text=True, input=input)


def api(path, data=None):
    if data is not None:
        return json.loads(github('api', path, '--method', 'POST', '--input', '-', input=json.dumps(data)))
    return json.loads(github('api', path))


def trusted_context():
    if (os.environ.get('GITHUB_REPOSITORY') != SOURCE
            or os.environ.get('GITHUB_REF') != 'refs/heads/main'
            or os.environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch'):
        raise ValueError('release requires workflow_dispatch on the source repository main branch')


def source_run(run_id, sha):
    trusted_context()
    if not re.fullmatch(r'[1-9]\d*', run_id) or not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('expected numeric run ID and full source commit SHA')
    run = api(f'repos/{SOURCE}/actions/runs/{run_id}')
    if not (str(run['id']) == run_id and run['head_sha'] == sha
            and run['head_branch'] == 'main' and run['event'] == 'workflow_dispatch'
            and run['path'] == '.github/workflows/release-candidate.yml'
            and run['status'] == 'completed' and run['conclusion'] == 'success'
            and run['repository']['full_name'] == SOURCE
            and run['head_repository']['full_name'] == SOURCE):
        raise ValueError('source run must be a trusted successful candidate for the exact commit')
    comparison = api(f'repos/{SOURCE}/compare/{sha}...main')
    if comparison['status'] != 'identical':
        raise ValueError('candidate must still be current main; prepare a fresh candidate after main changes')
    artifacts = api(f'repos/{SOURCE}/actions/runs/{run_id}/artifacts?per_page=100')
    candidates = [item for item in artifacts['artifacts']
                  if item['name'].startswith(f'release-candidate-{run_id}-')]
    # A failed-jobs retry retains its successful producer. A full rebuild is ambiguous:
    # dispatch a new candidate instead of guessing which bytes the runtime jobs tested.
    if artifacts['total_count'] > 100 or len(candidates) != 1 or candidates[0]['expired']:
        raise ValueError('expected one unexpired candidate artifact; dispatch a fresh candidate')
    artifact_id = str(candidates[0]['id'])
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f'artifact-id={artifact_id}\n')
    print(artifact_id)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def asset_names(number, build):
    stem = f'MonsterDeleter-{number}-build{build}-macos15-universal'
    return [f'{stem}.zip', f'{stem}.dmg', 'INSTALL.txt', 'SHA256SUMS.txt']


def stage(tag):
    trusted_context()
    number, build = version(tag)
    app = ROOT / 'build/MonsterDeleter.app'
    version(tag, plistlib.loads((app / 'Contents/Info.plist').read_bytes()))
    subprocess.run(['scripts/check-app.sh', str(app)], check=True, cwd=ROOT)
    subprocess.run(['xcrun', 'stapler', 'validate', str(app)], check=True)
    subprocess.run(['spctl', '--assess', '--type', 'execute', str(app)], check=True)
    dmg = ROOT / f'build/MonsterDeleter-{number}.dmg'
    subprocess.run(['xcrun', 'stapler', 'validate', str(dmg)], check=True)
    subprocess.run(['spctl', '--assess', '--type', 'open', '--context',
                    'context:primary-signature', str(dmg)], check=True)
    destination = ROOT / 'build/release'
    destination.mkdir()  # Never quietly reuse an earlier candidate directory.
    names = asset_names(number, build)
    for name, suffix in zip(names, ('zip', 'dmg')):
        shutil.copyfile(ROOT / f'build/MonsterDeleter-{number}.{suffix}', destination / name)
    shutil.copyfile(ROOT / 'Packaging/INSTALL.txt', destination / 'INSTALL.txt')
    checksums = ''.join(f'{sha256(destination / name)}  {name}\n' for name in names[:3])
    (destination / 'SHA256SUMS.txt').write_text(checksums)
    sha = os.environ['GITHUB_SHA']
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('expected full source commit SHA')
    body = (f'# MonsterDeleter {number} (build {build})\n\n'
            'Summon a monster from Finder to move a file, folder or selection to the Trash. '
            'Includes Kaiju, Cat and UFO character packs. Esc cancels before impact.\n\n'
            'Requires macOS 15 or later. One universal app for Apple silicon and Intel. '
            'Signed with Developer ID, notarized by Apple, with stapled tickets.\n\n'
            'Download the DMG, open it and drag MonsterDeleter to Applications. '
            'Alternatively, extract the ZIP and move the app to Applications. '
            'Quit any older copy first, then open the installed app and follow its introduction. '
            'In Finder choose Services > Feed to Monster on your selection. '
            'See INSTALL.txt for verification and first-use steps.\n\n'
            f'Source commit: `{sha}`. Native macOS 15 ARM and Intel checks must pass '
            'on this exact ZIP before publication. Physical recipient hardware acceptance is a separate check.\n\n'
            f'```text\n{checksums}```\n')
    (destination / 'release-notes.md').write_text(body)
    manifest = dict(tag=tag, version=number, build=build, source_commit=sha,
                    source_run=os.environ['GITHUB_RUN_ID'], signing='developer-id-notarized',
                    assets={name: sha256(destination / name) for name in names},
                    body_sha256=sha256(destination / 'release-notes.md'))
    (destination / 'candidate.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(body)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            summary.write(body)


def verify(directory, tag, sha, run_id):
    manifest = json.loads((directory / 'candidate.json').read_text())
    number, build = version(tag, {'CFBundleShortVersionString': manifest['version'],
                                 'CFBundleVersion': manifest['build']})
    names = asset_names(number, build)
    if (manifest['tag'] != tag or manifest['source_commit'] != sha
            or manifest['source_run'] != run_id
            or manifest['signing'] != 'developer-id-notarized'):
        raise ValueError('candidate identity/signing does not match the approved run')
    if (set(manifest['assets']) != set(names)
            or set(item.name for item in directory.iterdir()) != set(names + ['candidate.json', 'release-notes.md'])):
        raise ValueError('candidate contains unexpected files; only intended release assets are allowed')
    for name in names + ['release-notes.md']:
        expected = manifest['body_sha256'] if name == 'release-notes.md' else manifest['assets'][name]
        if (directory / name).is_symlink() or sha256(directory / name) != expected:
            raise ValueError(f'candidate checksum mismatch: {name}')
    expected_checksums = ''.join(f'{manifest["assets"][name]}  {name}\n' for name in names[:3])
    if (directory / 'SHA256SUMS.txt').read_text() != expected_checksums:
        raise ValueError('SHA256SUMS does not match candidate assets')
    return manifest


def publish(directory, tag, sha, run_id):
    trusted_context()
    manifest = verify(directory, tag, sha, run_id)
    if os.environ.get('GITHUB_SHA') != sha:
        raise ValueError('reviewed candidate must match this main dispatch commit')
    target = SOURCE
    repository = api(f'repos/{target}')
    if repository['private']:
        raise ValueError('source repository must already be public; no visibility changes are automated')
    releases = json.loads(github('api', f'repos/{target}/releases?per_page=100', '--paginate', '--slurp'))
    existing = [release for page in releases for release in page if release['tag_name'] == tag]
    if len(existing) > 1:
        raise ValueError('ambiguous release tag')
    body = (directory / 'release-notes.md').read_text()
    title = f'MonsterDeleter {manifest["version"]} (build {manifest["build"]})'
    if existing:
        release = existing[0]
        if not release['draft']:
            raise ValueError('version is already published; never overwrite a published release')
        if release['body'] != body or release['name'] != title or release['prerelease']:
            raise ValueError('existing draft differs from candidate; operator reconciliation required')
        target_sha = release['target_commitish']
    else:
        target_sha = sha
    if target_sha != sha:
        raise ValueError('release target must match the exact reviewed source commit')
    # Query matching refs (including an absent tag) without treating auth/network errors as absence.
    refs = api(f'repos/{target}/git/matching-refs/tags/{tag}')
    exact = [ref for ref in refs if ref['ref'] == f'refs/tags/{tag}']
    if exact and (not existing or exact[0]['object']['sha'] != target_sha
                  or exact[0]['object']['type'] != 'commit'):
        raise ValueError('tag already exists or moved; never overwrite or move a version tag')
    if not existing:
        release = api(f'repos/{target}/releases', dict(tag_name=tag, target_commitish=target_sha,
                      name=title, body=body, draft=True, prerelease=False))
        if (not isinstance(release, dict) or type(release.get('id')) is not int or release['id'] <= 0
                or release.get('draft') is not True or release.get('prerelease') is not False
                or release.get('tag_name') != tag or release.get('target_commitish') != target_sha
                or release.get('name') != title or release.get('body') != body):
            raise ValueError('release creation response differs from candidate; refusing uploads')
    assets = api(f'repos/{target}/releases/{release["id"]}/assets?per_page=100')
    expected = manifest['assets']
    seen = set()
    for asset in assets:
        name = asset['name']
        if (name not in expected or name in seen or asset['state'] != 'uploaded'
                or asset.get('digest') != 'sha256:' + expected[name]
                or asset['size'] != (directory / name).stat().st_size):
            raise ValueError('draft asset differs from candidate; no replacement is allowed')
        seen.add(name)
    for name in expected.keys() - seen:
        github('release', 'upload', tag, str(directory / name), '--repo', target)
    uploaded = api(f'repos/{target}/releases/{release["id"]}/assets?per_page=100')
    if (len(uploaded) != len(expected)
            or {asset['name']: asset.get('digest') for asset in uploaded} !=
            {name: 'sha256:' + digest for name, digest in expected.items()}
            or any(asset['state'] != 'uploaded' or asset['size'] != (directory / asset['name']).stat().st_size
                   for asset in uploaded)):
        raise ValueError('uploaded asset verification failed; release remains a draft')
    current = api(f'repos/{target}/releases/{release["id"]}')
    if (not current['draft'] or current['body'] != body or current['target_commitish'] != target_sha
            or current['tag_name'] != tag or current['prerelease'] or current['name'] != title):
        raise ValueError('draft changed during upload; refusing publication')
    refs = api(f'repos/{target}/git/matching-refs/tags/{tag}')
    exact = [ref for ref in refs if ref['ref'] == f'refs/tags/{tag}']
    if exact:
        if exact[0]['object']['type'] != 'commit' or exact[0]['object']['sha'] != target_sha:
            raise ValueError('tag changed during upload; refusing publication')
    else:
        # Create-only API: a concurrent tag creation fails instead of moving its reference.
        github('api', f'repos/{target}/git/refs', '--method', 'POST',
               '-f', f'ref=refs/tags/{tag}', '-f', f'sha={target_sha}')
    github('release', 'edit', tag, '--repo', target, '--draft=false', '--latest=true')
    print(f'https://github.com/{target}/releases/tag/{tag}')
    print(f'https://github.com/{target}/releases/latest')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    check = commands.add_parser('version')
    check.add_argument('tag')
    source = commands.add_parser('source-run')
    source.add_argument('run_id')
    source.add_argument('sha')
    prepare = commands.add_parser('stage')
    prepare.add_argument('tag')
    for name in ('verify', 'publish'):
        command = commands.add_parser(name)
        command.add_argument('directory', type=Path)
        command.add_argument('tag')
        command.add_argument('sha')
        command.add_argument('run_id')
    commands.add_parser('context')
    args = parser.parse_args()
    if args.command == 'version':
        version(args.tag)
        print(args.tag)
    elif args.command == 'stage':
        stage(args.tag)
    elif args.command == 'context':
        trusted_context()
    elif args.command in ('verify', 'publish'):
        action = verify if args.command == 'verify' else publish
        action(args.directory, args.tag, args.sha, args.run_id)
    elif args.command == 'source-run':
        source_run(args.run_id, args.sha)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f'release: {error}')
