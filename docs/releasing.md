# GitHub downloads

Source and downloads share the existing
`kuan0808/MonsterDeleter` repository. The operator owns the visibility change after the
tracked-source/history and provenance review. Release automation never creates repositories,
changes visibility, exports credentials, or publishes from a pull request, fork, or non-main
branch. GitHub's automatic source archives contain this repository's tagged source.

## One-time operator setup

1. Complete the source/history secret and code/assets/license review, then make the existing
   repository public. Preserve third-party notices; resolve the root project license before
   calling the source open source. Automation requires the already public source repository.
2. Enable immutable releases when available and protect version tags against update/deletion.
   Automation independently refuses published versions.
3. Supply these six signing/notarization Actions secrets to the source repository. No personal
   GitHub token, cross-repository token or target variable is needed.

| Secret | Required value and scope |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 of an operator-supplied password-protected P12 containing a Developer ID Application certificate and its private key. An Apple Development certificate does not qualify. |
| `DEVELOPER_ID_P12_PASSWORD` | Password for that P12. |
| `CODESIGN_IDENTITY` | Exact `Developer ID Application: ...` identity in that P12. |
| `NOTARY_APPLE_ID` | Apple ID authorized to notarize for the signing team. |
| `NOTARY_TEAM_ID` | That Apple Developer team ID. |
| `NOTARY_PASSWORD` | App-specific password for the notarization Apple ID, not the account password. |

The publish job uses the built-in `GITHUB_TOKEN` with Contents: write and Actions: read.
Candidate builds have Contents: read and cannot publish. Signing credentials
are imported into a temporary hosted-runner keychain, removed in an `always()` cleanup step,
and never uploaded as artifacts. Apple Developer Program membership and certificate issuance
are operator prerequisites, not actions performed by these scripts. Missing credentials fail
before building a public candidate. There is no automatic ad hoc fallback.

## Prepare a version

1. Change `CFBundleShortVersionString` and/or increment `CFBundleVersion` in
   `Packaging/Info.plist` through a reviewed change. Every distributed bundle change needs a
   new build number. Never reuse a published tag. `v<version>-build<build>` must match both
   fields exactly, for example `v0.4.0-build7`. Do not hand-edit generated CHANGELOG content.
2. Merge through the normal source review/CI process, then dispatch from main:

   ```sh
   gh-axi workflow run release-candidate.yml --ref main --field tag=v0.4.0-build7
   ```

3. Wait for the complete **Release candidate** run to succeed. It reuses `ci.yml`: universal
   build, Swift tests, lint, packaging checks, Developer ID signing, app notarization/stapling,
   and DMG signing/notarization/stapling. The DMG is made from the stapled app without a rebuild.
   It is mounted read-only and compared against the ZIP's app. The existing native macOS 15
   ARM and Intel jobs check the exact final ZIP and executable hashes, signature, confirmation,
   cancellation, checkpoint references and active executable slice. No compiler runs there.
4. Download the `release-candidate-<run-id>-<producer-attempt>` artifact for review.
   `candidate.json` binds version/build, exact source SHA, source run, signing state and all
   hashes. `release-notes.md` is the exact proposed public body. The same body appears in the
   build job summary, which alone is not proof the later runtime jobs passed.

Only these four files will be attached to the public Release:

- `MonsterDeleter-<version>-build<build>-macos15-universal.dmg`
- `MonsterDeleter-<version>-build<build>-macos15-universal.zip`
- `SHA256SUMS.txt` (hashes of both archives and INSTALL.txt)
- `INSTALL.txt`

Candidate metadata and CI reports are not release assets. Actions logs and artifacts are visible
under the repository’s access rules, including after the repository becomes public. Public notes
carry the source commit hash. Only intended user downloads are attached;
CI reports, fixtures, credentials and generated source changelogs are not release assets.
The [recipient checklist](compatibility.md#recipient-acceptance) covers hands-on installation.
Native runner success does not certify a particular physical laptop's UI or performance.

## Publish the reviewed bytes

Before dispatch, record the exact target, tag, source SHA, successful run ID, asset hashes,
public notes, signing state and this filled-in command in the operator's private release report.
Publication requires explicit release authority; preparing a candidate grants none.

```sh
gh-axi workflow run release.yml --ref main \
  --field tag=v0.4.0-build7 \
  --field source_run=SUCCESSFUL_CANDIDATE_RUN_ID \
  --field source_commit=FULL_40_CHARACTER_SOURCE_SHA
```

The workflow validates the run's repository, workflow, main branch, event, exact SHA, completed
success and that the candidate is still current main. The publish dispatch must use the same
commit; if main advances, prepare a fresh candidate. This also keeps tag creation within the
built-in token's permissions, without granting access to modify workflows. It downloads the unique unexpired candidate by artifact ID, checks
its entire file allowlist and hashes, and publishes only after verifying a complete draft's
remote asset SHA-256 digests and sizes. The release tag and body both pin the exact reviewed app source commit. No code or git history
is copied across repositories.

The stable user link is `https://github.com/kuan0808/MonsterDeleter/releases/latest`.
After publishing, verify the public release and download both archives through that route,
check SHA-256, and record normal Finder installation/Gatekeeper acceptance on an approved test
Mac. Never strip quarantine or disable Gatekeeper. A signed build is not claimed accepted on a
recipient machine until that route has actually been tested.

## Failure and retry

- A failed-jobs candidate rerun retains the successful producer artifact's ID even when the
  run attempt changes. A full rerun can produce multiple candidates; publication rejects that
  ambiguity. Dispatch a fresh candidate run, rather than guessing which artifact passed.
- Failed notarization, runtime checks, missing/expired artifacts or wrong source runs cannot
  publish. Downloading an ordinary PR/ad hoc CI artifact is not a stable-release route.
- A failed upload leaves a draft. Dispatch the identical publish command again: only a draft
  with the same title/body, target commit and matching uploaded assets can resume. Existing
  files are never overwritten. A mismatched draft/asset requires operator reconciliation;
  the workflow does not delete evidence or replace it automatically.
- A published tag or a pre-existing unrelated tag stops publication. A retry after successful
  publication also stops; inspect the existing Release rather than publishing it twice.
- Expired candidate artifacts require a new candidate and review of its new hashes. Never
  relabel an older ad hoc ZIP as a notarized candidate.

If signing setup must wait, a clearly marked **unnotarized prerelease** could be a separate
operator-approved delivery choice. It is deliberately not a switch or fallback in this stable
pipeline. The existing CI ad hoc artifacts remain available for that evaluation;
Gatekeeper acceptance is not implied and quarantine removal is never an installation step.

## Validation and references

`python3 -m unittest discover -s scripts/tests -v` checks the release command boundary, replacing
only GitHub's external CLI in local fixtures. `actionlint` checks workflow expressions and
`shellcheck scripts/release-signing.sh scripts/notarize.sh scripts/package.sh` checks the shell
changes when those tools are installed. Hosted jobs use the standard preinstalled `gh` CLI;
operators on this project use `gh-axi` to dispatch and inspect workflows.

[GitHub release drafts and immutable releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository),
[GitHub Actions secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets),
[GitHub release asset digests](https://docs.github.com/en/rest/releases/assets),
[Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
