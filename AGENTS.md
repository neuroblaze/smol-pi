# AGENTS.md

Notes for agents (and humans) working on this repo.

## Release flow

smol-pi uses annotated git tags for releases. There is no CI build step —
`install.sh` fetches files directly from `raw.githubusercontent.com` at a
tagged ref, so a tag is all that's needed for a release.

### Bumping the version

1. Edit `install.sh` and bump `VERSION="vX.Y.Z"` at the top of the file.
   This is the default tag the installer fetches.
2. Update the install URLs in `README.md` to point at the new tag
   (`raw.githubusercontent.com/neuroblaze/smol-pi/vX.Y.Z/install.sh`).
   There are two occurrences in the Install section.
3. Commit both files. Suggested message:
   `Bump install.sh default to vX.Y.Z`
4. Push main, then tag and push the tag:
   ```sh
   git push origin main
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```
5. Create a GitHub Release from the tag (this is what makes
   `install.sh --version latest` resolve — it queries the releases API, not
   just tags):
   ```sh
   gh release create vX.Y.Z --title "vX.Y.Z" --notes "<short summary>"
   ```

A plain `git push --tags` is enough for `--version vX.Y.Z` to work
(raw.githubusercontent.com serves tags as refs), but `--version latest`
needs the GitHub Release object to exist.

### Versioning scheme

Semantic versioning, starting at v1.0.1 (v1.0.0 was skipped — people
distrust 1.0.0). The tag and the `VERSION` in `install.sh` must always
match. The README install command references the same tag.

### What counts as a release

Anything a user would want to pin to: a new feature, a behaviour change,
or a fix. Pure internal refactors with no user-visible effect don't need a
release. When in doubt, cut one — tags are cheap.

## Repo layout

- `smol-pi` — launcher script (boots the VM)
- `smol-pi-build` — image builder (podman/docker)
- `install.sh` — one-line installer (pinned to a release tag)
- `Dockerfile.pi` — image definition (also embedded in `smol-pi-build`
  via a heredoc so `--generate-dockerfile` works without the repo)
- `scripts/compute_cidrs.py` — generates the CIDR allowlist blocks in
  `smol-pi`; rerun if the network-mode filtering needs adjusting
- `TODO` — improvement ideas and findings
- `security_audit.md` — notes from a security review of the sandbox
- `pi-shift-enter.keytab` — leftover from a removed SSH transport; kept
  for reference

All scripts are POSIX `sh` (not bash) — syntax-check with `sh -n` before
committing.

## Conventions

- No comments added to code unless asked.
- Scripts must pass `sh -n`. There's no test suite or linter; the
  `sh -n` check is the gate.
- Don't commit `security_audit.md` changes unless explicitly asked — it's
  a standalone review artifact, not part of the build.
- Don't tag or push tags/releases unless explicitly asked.