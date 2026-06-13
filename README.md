# nsp-github-cam-bundle

GitHub-ready project to **repack** the **`nsp-ne-backup`** artifact bundle using the vendored **Go** [`artifact-bundle-builder`](./builder/VENDOR.md), then (optionally) **upload** to NSP file service and **install** via CAM REST.

This repo is scoped to the **`cam-lso-deployer-app`** pilot: bundle name **`nsp-ne-backup`**, install drives LSO-related deployer work. Use a **non-production** lab.

## Layout

| Path | Purpose |
| ---- | ------- |
| [`builder/`](./builder/) | Vendored `main.go`, `artifact-meta.go`, `go.mod` from [`build-cam-artifact-bundle-builder`](../build-cam-artifact-bundle-builder). |
| [`source-bundle/`](./source-bundle/) | Input directory: `metadata.json` + `content/` (builder input shape; no `artifact-content` in metadata). |
| [`scripts/repack.sh`](./scripts/repack.sh) | `go build` + run builder; writes **`dist/*.zip`**. Default **`-unsigned`**. |
| [`scripts/extract-reference-zip.sh`](./scripts/extract-reference-zip.sh) | Unzip a reference **`nsp-ne-backup-1.41.0.zip`** into `source-bundle/` (then run [`strip-artifact-content.py`](./scripts/strip-artifact-content.py) if metadata still lists digests). |
| [`scripts/upload-and-install.sh`](./scripts/upload-and-install.sh) | `curl` upload to file service + `POST /cam/rest/api/v1/artifactBundle/install` with JSON `{"bundles":["<zip-basename>"]}`. |
| [`postman/cam-v3.json`](./postman/cam-v3.json) | OpenAPI export for CAM (v1 or v2 or v3 paths); align **`servers[0].url`** with your lab. |
| [`reference/`](./reference/README.md) | Optional place for **`nsp-ne-backup-1.41.0.zip`**; see README for compliance notes. |
| [`.env.example`](./.env.example) | Template for **`NSP_BASE_URL`** / **`CAM_TOKEN`**; copy to **`.env`** (gitignored). |

## Local build

```bash
./scripts/repack.sh
ls -la dist/
```

Environment overrides:

| Variable | Effect |
| -------- | ------ |
| `UNSIGNED=0` | Signed build; set **`AUTHOR`** and **`PK_FILE`** (PEM path). |
| `BUNDLE_VERSION_OVERRIDE` | Passed as **`-version`** to the builder. |

## Upload and install (lab)

**Do not commit JWTs.** Put secrets in repo-root **`.env`** (gitignored) or export them in your shell.

1. `cp .env.example .env`
2. Set **`CAM_TOKEN=`** in **`.env`** to your JWT string only (no `Bearer ` prefix). **`NSP_BASE_URL`** defaults to **`https://100.120.90.89`** in the example; change if your lab differs.
3. Run:

```bash
./scripts/repack.sh
./scripts/upload-and-install.sh
```

[`scripts/upload-and-install.sh`](./scripts/upload-and-install.sh) automatically **`source`s** **`.env`** from the repo root when the file exists.

**CAM vs file service:** bundle **upload** uses the **file service** REST API (still **`/nsp-file-service-app/rest/api/v1/file/uploadFile`** in typical NSP installs). **Install** is a **CAM** call; this repo defaults to **v3** batch install: **`POST {NSP_BASE_URL}{CAM_BASE_PATH}/rest/api/v3/artifactBundle/install`** with JSON **`{"bundles":["<zip-basename>"]}`** (see [ARCH NSPF-264170](../rags-nsp-docs/cam-docs/camapi-v3/ARCH_NSPF-264170_CAM_API_Hardening_v3.md)). Override with **`CAM_REST_API_VERSION=v1`** or **`v2`** if your cluster does not expose v3 yet.

**GitHub Actions:** in the repo on GitHub, add repository secrets **`NSP_BASE_URL`** (`https://100.120.90.89`) and **`CAM_TOKEN`** (same JWT). Manual workflow: [`.github/workflows/deploy-nsp-lab.yml`](./.github/workflows/deploy-nsp-lab.yml).

**Network:** **`deploy-nsp-lab`** on **GitHub-hosted** `ubuntu-latest` cannot open **`https://100.120.x.x`** inside your lab (runners are on the public internet). You will see **`curl: (28) Failed to connect`**. Use a **self-hosted** runner inside the lab/VPN, or run **`./scripts/upload-and-install.sh`** from a host that can reach NSP, or only use Actions for **`build-repack-nsp-ne-backup`** (artifact) and deploy manually.

If a token was ever pasted into a ticket, chat, or a tracked file, **rotate** it in your IdP and update **`.env`** / secrets.

Optional: **`BUNDLE_ZIP`**, **`FS_UPLOAD_PATH`**, **`CAM_BASE_PATH`**, **`BUNDLE_FILE_NAME`** (see script header).

Upload uses the same pattern as the CAM UI: **`POST .../nsp-file-service-app/rest/api/v1/file/uploadFile?dirName=/nokia/nsp/cam/artifacts/bundle&overwrite=true`** with multipart **`file`**.

## Documentation

Implementation plan and northbound context: [`rags-nsp-docs/inno-ideas/cam-northbound/cam-northbound-github-integration-implementation-plan.md`](../rags-nsp-docs/inno-ideas/cam-northbound/cam-northbound-github-integration-implementation-plan.md).

## CI

Workflow **[`.github/workflows/build-repack-nsp-ne-backup.yml`](./.github/workflows/build-repack-nsp-ne-backup.yml)** builds on push to **`main`** or **`master`** when files change under **`source-bundle/`**, **`builder/`**, **`scripts/`**, or that workflow file; it also runs on **`pull_request`** with the same path filters and on **`workflow_dispatch`** (manual, no path filter). It uploads **`dist/*.zip`** as a workflow artifact.

**[`deploy-nsp-lab.yml`](./.github/workflows/deploy-nsp-lab.yml)** is manual-only; set secrets **`NSP_BASE_URL`** (e.g. `https://100.120.90.89`) and **`CAM_TOKEN`** (JWT without `Bearer `) under **Settings → Secrets and variables → Actions**.

### Build locally (same as CI)

```bash
cd /path/to/nsp-github-cam-bundle
chmod +x scripts/repack.sh
./scripts/repack.sh
ls -la dist/*.zip
```

Requires **Go 1.17+** on your PATH (CI uses **1.22**).

### Trigger the build workflow on GitHub

1. **Push** a commit on **`master`** or **`main`** that touches at least one path listed above, **or**
2. **Actions** tab in GitHub: select **build-repack-nsp-ne-backup** then **Run workflow** (uses **`workflow_dispatch`**), **or**
3. From a clone with [`gh`](https://cli.github.com/) authenticated:

```bash
cd /path/to/nsp-github-cam-bundle
git checkout master   # or main
gh workflow run build-repack-nsp-ne-backup.yml --ref master
gh run list --workflow=build-repack-nsp-ne-backup.yml --limit 3
```

### Trigger deploy to lab (upload + install)

**Runner:** **`deploy-nsp-lab`** uses **`runs-on: [self-hosted, windows, x64]`** so the job runs on your **Windows x64** self-hosted agent (for example **`C-PF68KS1H`**) that can reach the lab. Register the runner under **Settings → Actions → Runners** for this repository (or the org). New Windows runners get the labels **`self-hosted`**, **`Windows`**, and **`X64`** by default; GitHub matches labels **case-insensitively**, so **`windows`** / **`x64`** in the workflow still match.

To **pin only one machine**, add a **custom label** (e.g. **`C-PF68KS1H`**) to that runner in the GitHub UI, then change **`.github/workflows/deploy-nsp-lab.yml`** to:

```yaml
runs-on: [self-hosted, C-PF68KS1H]
```

**Software on the runner:** **Git for Windows** (must include **`C:\Program Files\Git\bin\bash.exe`**). The deploy workflow uses **`shell: pwsh`** and invokes that Bash explicitly so **`C:\Windows\System32\bash.exe`** (WSL) is not picked first; WSL breaks Actions temp script paths (error like **`C:ragsNSPpersactions-runner...sh: No such file or directory`**). Also **Go 1.22+** and **curl** on `PATH` (Windows 10+ includes **curl.exe**).

After repository secrets **`NSP_BASE_URL`** and **`CAM_TOKEN`** are set:

```bash
gh workflow run deploy-nsp-lab.yml --ref master
```

**Security:** Do not embed GitHub PATs or JWTs in `git remote` URLs. Use **`gh auth login`**, SSH remotes, or a credential helper, and rotate any token that was stored in plain text.
