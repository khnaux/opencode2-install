# Publishing this to GitHub

Two formats work well:

- **A repo** — the installer plus `README.md` as the tutorial.
- **A gist** — `README.md` alone, if you only want the write-up.

> **This copy lives on Android shared storage** (`/storage/emulated/0/opencode2-install`).
> Three things to know:
>
> - Git refuses to touch it until the path is trusted:
>   `git config --global --add safe.directory /storage/emulated/0/opencode2-install`
> - The sdcard mount ignores file modes, so `core.fileMode` is already set to `false`.
> - The mount is `noexec`: run the installer as `bash install-opencode2.sh`, never `./install-opencode2.sh`.

Published at <https://github.com/khnaux/opencode2-install>. The steps below are for
re-publishing from a fresh clone, moving it to another account, or setting up a second machine.

---

## 1. Install the tools

```bash
pkg install git gh
gh auth login          # GitHub.com -> HTTPS -> login with a browser or a token
```

`gh auth login` is interactive on purpose: do not paste a token into a chat window.

## 2. Create the repo and push

From inside this folder:

```bash
cd /storage/emulated/0/opencode2-install

git init -b main
git add install-opencode2.sh README.md PUBLISH.md
git commit -m "Add OpenCode 2.x installer and guide"

# creates the repo on your account and sets 'origin'
gh repo create opencode2-install --public --source=. --remote=origin --push
```

Without `gh`, create an empty repo at <https://github.com/new>, then:

```bash
git remote add origin git@github.com:khnaux/opencode2-install.git
git push -u origin main
```

## 3. Publish the guide as a gist (optional)

```bash
gh gist create README.md --public --desc "Install OpenCode 2.x on Linux, macOS and Termux"
```

A gist renders markdown and is the quickest way to get a shareable "post". If you want it to
read like an article, add a title heading and keep the sections in order — the README already
does.

## 4. Optional polish

```bash
# MIT license so people can reuse the script
curl -fsSL https://raw.githubusercontent.com/licenses/license-templates/master/templates/mit.txt \
  -o LICENSE
# then replace <year> and <copyright holders> in that file

# make the script executable in the repo (it already is locally)
git update-index --chmod=+x install-opencode2.sh

git add LICENSE
git commit -m "Add MIT license"
git push
```

## 5. Keep it current

The installer resolves the newest 2.x from
`https://opencode.ai/update/api/latest/cli/npm`, so it does not need edits per release.
The only line that ages is the "Verified against OpenCode X.Y.Z" note in `README.md` —
update it when you re-test, e.g.:

```bash
bash install-opencode2.sh --dry-run   # prints the resolved version
```

A small CI job that runs `--dry-run` weekly is enough to catch a channel that stops
serving 2.x:

```yaml
# .github/workflows/install-check.yml
name: install-check
on:
  schedule: [{ cron: "0 6 * * 1" }]
  workflow_dispatch:
jobs:
  dry-run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash install-opencode2.sh --dry-run
```
