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
| [`scripts/upload-and-install.sh`](./scripts/upload-and-install.sh) | `curl` upload (`createDirectory=true`) unless **`SKIP_FILE_SERVICE_UPLOAD=1`**, then **`POST /cam/rest/api/<v>/artifactBundle/install`** (auto **`v3`/`v2`/`v1`** or **`v3`** only when skipping upload). |
| [`postman/cam-v3.json`](./postman/cam-v3.json) | OpenAPI export for CAM (v1 or v2 or v3 paths); align **`servers[0].url`** with your lab. |
| [`reference/`](./reference/README.md) | Optional place for **`nsp-ne-backup-1.41.0.zip`**; see README for compliance notes. |
| [`.env.example`](./.env.example) | Template for **`NSP_BASE_URL`** / **`CAM_TOKEN`**; copy to **`.env`** (gitignored). |

## Why file service before CAM install?

**CAM batch install does not accept the ZIP in the HTTP body.** It only accepts JSON listing bundle **file names** (for example `nsp-ne-backup-1.41.0.zip`). For each name, CAM resolves the object on the **NSP file service** under **`/nokia/nsp/cam/artifacts/bundle/`**, verifies it (checksum), then extracts and reconciles. See **`cam-server-app`** [`ArtifactBundleRestService.java`](../cam-server-app/src/main/java/com/nokia/nsp/cam/rest/service/ArtifactBundleRestService.java) (`fileService.getCheckSumWithResult` on **`Constants.ARTIFACT_BASE_PATH + "/" + artifactBundleName`** before install).

Automation must **upload the ZIP to the file service bundle directory first**, then call CAM install. Same pattern as the CAM UI and [`cam-tools`](../cam-tools/src/processer.py). Bundle paths and behavior: [`ARTIFACTS_AND_BUNDLES.md`](../rags-nsp-docs/cam-docs/ARTIFACTS_AND_BUNDLES.md).

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

**Debug logging:** set **`UPLOAD_INSTALL_DEBUG=1`** or **`DEBUG=1`** in **`.env`** (or enable **Actions** re-run with debug logging so **`ACTIONS_STEP_DEBUG=true`**). Logs go to **stderr** with prefix **`[upload-and-install]`**; extra lines use **`[upload-and-install][debug]`**. **`CAM_TOKEN`** is never printed. In GitHub, set repository **Variable** **`UPLOAD_INSTALL_DEBUG`** to **`1`** (optional; wired in **`deploy-nsp-lab.yml`**).

**CAM vs file service:** bundle **upload** uses the **file service** REST API (**`/nsp-file-service-app/rest/api/v1/file/uploadFile`**) with **`createDirectory=true`** so **`/nokia/nsp/cam/artifacts/bundle`** is created if missing (otherwise the API returns **HTTP 404**). **Install** calls **`POST {NSP_BASE_URL}{CAM_BASE_PATH}/rest/api/<v>/artifactBundle/install`** with JSON **`{"bundles":["<zip-basename>"]}`**. If **`CAM_REST_API_VERSION`** is **unset**, the script tries **`<v>` = `v3`**, then **`v2`**, then **`v1`** (gateways often expose only one). Set **`CAM_REST_API_VERSION`** to use a single version. See [ARCH NSPF-264170](../rags-nsp-docs/cam-docs/camapi-v3/ARCH_NSPF-264170_CAM_API_Hardening_v3.md).

**Install only (no upload API):** if you copied **`*.zip`** into **`.../nokia/nsp/cam/artifacts/bundle/`** on the file-service volume (same path CAM uses), set **`SKIP_FILE_SERVICE_UPLOAD=1`** and **`BUNDLE_FILE_NAME=nsp-ne-backup-1.41.0.zip`** (or keep a local **`dist/*.zip`** so the script can take the basename). Install then defaults to **v3 only** unless **`CAM_REST_API_VERSION`** is set.

**GitHub Actions:** in the repo on GitHub, add repository secrets **`NSP_BASE_URL`** (`https://100.120.90.89`) and **`CAM_TOKEN`** (same JWT). Manual workflow: [`.github/workflows/deploy-nsp-lab.yml`](./.github/workflows/deploy-nsp-lab.yml).

**Network:** **`deploy-nsp-lab`** on **GitHub-hosted** `ubuntu-latest` cannot open **`https://100.120.x.x`** inside your lab (runners are on the public internet). You will see **`curl: (28) Failed to connect`**. Use a **self-hosted** runner inside the lab/VPN, or run **`./scripts/upload-and-install.sh`** from a host that can reach NSP, or only use Actions for **`build-repack-nsp-ne-backup`** (artifact) and deploy manually.

If a token was ever pasted into a ticket, chat, or a tracked file, **rotate** it in your IdP and update **`.env`** / secrets.

Optional: **`BUNDLE_ZIP`**, **`FS_UPLOAD_PATH`**, **`CAM_BASE_PATH`**, **`BUNDLE_FILE_NAME`**, **`CURL_*`** (see script header).

**Windows / lab TLS:** Git **`mingw64/bin/curl.exe`** (common when **`usr/bin/curl.exe`** is absent) still uses **Schannel**; use a trusted lab CA, **`CURL_CA_BUNDLE`**, or **`NSP_TLS_INSECURE=1`** (non-production). In **GitHub Actions**, **`upload-and-install.sh`** defaults **`NSP_TLS_INSECURE=1`** when unset (see CI section). For **`curl: (26) Failed to open/read local data`** on multipart upload, the script uses **`cygpath -w`** for the **`file=@...`** path when **`cygpath`** is available so MinGW/Schannel curl can open the ZIP.

Upload uses the same pattern as the CAM UI: **`POST .../nsp-file-service-app/rest/api/v1/file/uploadFile?dirName=/nokia/nsp/cam/artifacts/bundle&overwrite=true&createDirectory=true`** with multipart **`file`**.

**Troubleshooting `curl: (22)` / HTTP 404 on upload:** the file service returns **404** when **`dirName`** does not exist and **`createDirectory`** is not true; the script always sends **`createDirectory=true`**. **404 on install** immediately after a failed upload usually means the ZIP never reached the file service. If **upload succeeds** but **install** returns **404**, the REST gateway may not expose that API version; leave **`CAM_REST_API_VERSION`** unset so the script tries **`v3`**, **`v2`**, then **`v1`**, or set the version your NSP exposes.

### Windows: manual curl when you see `curl: (60)` (Schannel)

This environment cannot run your Windows runner or reach your lab (no Windows curl test from here). If **`NSP_TLS_INSECURE`** is unset locally, curl correctly refuses an untrusted lab chain (**`(60)`**). **Postman** often still works because **Settings → General → SSL certificate verification** is off, or trust differs from **Git MinGW curl + Schannel**.

**GitHub Actions:** **`upload-and-install.sh`** sets **`NSP_TLS_INSECURE=1`** by default when **`GITHUB_ACTIONS`** is true and the variable is unset or empty (no extra repo secret). To verify TLS in CI, set job env **`NSP_TLS_INSECURE: "0"`** in **`deploy-nsp-lab.yml`** and use a trusted CA or **`CURL_CA_BUNDLE`**.

**Local `.env`:** set **`NSP_TLS_INSECURE=1`** for non-production labs, or import the lab issuing CA into Windows and/or set **`CURL_CA_BUNDLE`** to a PEM bundle curl accepts.

**Manual test (Git Bash)** -- use a **Windows** path for **`file=@`** with MinGW curl; **`-k`** is the same knob as **`NSP_TLS_INSECURE=1`**:

```bash
TOKEN="paste-jwt-here-no-Bearer-prefix"
ZIP_WIN="C:/Users/you/Downloads/nsp-ne-backup-1.41.0.zip"
"/c/Program Files/Git/mingw64/bin/curl.exe" -k -sS -w "\nHTTP %{http_code}\n" \
  -X POST "https://100.120.90.89/nsp-file-service-app/rest/api/v1/file/uploadFile?dirName=/nokia/nsp/cam/artifacts/bundle&overwrite=true&createDirectory=true" \
  -H "Authorization: Bearer ${TOKEN}" \
  -F "file=@${ZIP_WIN};filename=$(basename "$ZIP_WIN")"
```

**Manual test (PowerShell)** -- call **`curl.exe`**, not the **`curl`** alias:

```powershell
$token = "paste-jwt-here-no-Bearer-prefix"
$zip = "C:\Users\you\Downloads\nsp-ne-backup-1.41.0.zip"
& curl.exe -k -sS -w "`nHTTP %{http_code}`n" `
  -X POST "https://100.120.90.89/nsp-file-service-app/rest/api/v1/file/uploadFile?dirName=/nokia/nsp/cam/artifacts/bundle&overwrite=true&createDirectory=true" `
  -H "Authorization: Bearer $token" `
  -F "file=@${zip};filename=$(Split-Path $zip -Leaf)"
```

Postman **Code** exports sometimes emit **`--form '=@C:/...'`** (missing the field name). For this API the part name must be **`file`**, as in **`-F "file=@C:/path/to.zip"`**.

### Postman (or any REST client): `uploadFile` checklist

The **`nsp-file-service-app`** handler expects **`POST /nsp-file-service-app/rest/api/v1/file/uploadFile`** with **multipart** data (see **`FileController.uploadFile`** in **`nsp-file-service-app`** in this workspace).

1. **Method and URL**  
   **`POST https://<lab-ip>/nsp-file-service-app/rest/api/v1/file/uploadFile`**  
   Query string (recommended): **`dirName=/demo1`** (or your target folder), **`overwrite=true`**, and **`createDirectory=true`** if that folder might not exist yet. Without **`createDirectory=true`**, a missing **`dirName`** yields **HTTP 404** (`DIR_NOT_EXIST`).

2. **Authorization**  
   **`Authorization: Bearer <JWT>`** with a token that has **WRITE** on the File Server UI app (**`nspui-file-server`** in code). If UAC denies write, the API returns **HTTP 403** with an **empty** body in some paths. Use the same class of **admin / system** token you use for CAM (for example **SystemAdmin** on **NSP**), not a minimal-scope client unless your IdP maps it to file-server **WRITE**.

3. **Body type**  
   **`body` → `form-data`** (multipart). Do **not** set **`Content-Type`** yourself to **`application/json`**. Let Postman set **`multipart/form-data`** and the boundary.

4. **Multipart keys**  
   - **`file`**: type **File**, pick a file (required part name is exactly **`file`**).  
   - You can put **`dirName`**, **`overwrite`**, **`createDirectory`** in the **query string** only, or repeat them as **form-data** text fields (Spring binds **`@RequestParam`** from either).

5. **TLS**  
   If Postman fails SSL but the browser works: **Settings → General → SSL certificate verification** (lab only), or import your lab CA.

6. **ZIP uploads**  
   **`.zip`** files are scanned for disallowed inner extensions; a bad archive can fail with **400** / validation errors even when non-zip uploads work.

7. **Compare with a working call**  
   Open browser **DevTools → Network** on **File Server** upload, then mirror **URL**, **method**, **query params**, and **`file`** part name in Postman.

## Documentation

Implementation plan and northbound context: [`rags-nsp-docs/inno-ideas/cam-northbound/cam-northbound-github-integration-implementation-plan.md`](../rags-nsp-docs/inno-ideas/cam-northbound/cam-northbound-github-integration-implementation-plan.md).

## CI

Workflow **[`.github/workflows/build-repack-nsp-ne-backup.yml`](./.github/workflows/build-repack-nsp-ne-backup.yml)** builds on push to **`main`** or **`master`** when files change under **`source-bundle/`**, **`builder/`**, **`scripts/`**, or that workflow file; it also runs on **`pull_request`** with the same path filters and on **`workflow_dispatch`** (manual, no path filter). It uploads **`dist/*.zip`** as a workflow artifact.

**[`deploy-nsp-lab.yml`](./.github/workflows/deploy-nsp-lab.yml)** is manual-only; set secrets **`NSP_BASE_URL`** (e.g. `https://100.120.90.89`) and **`CAM_TOKEN`** (JWT without `Bearer `) under **Settings → Secrets and variables → Actions**. TLS: the upload script defaults **`NSP_TLS_INSECURE=1`** on Actions when unset (lab). Override with job env **`NSP_TLS_INSECURE: "0"`** if you need strict verification. Optional repository **variables**: **`CAM_REST_API_VERSION`** pins the CAM install path (if unset with upload, **`upload-and-install.sh`** tries **`v3`**, **`v2`**, **`v1`**). **`SKIP_FILE_SERVICE_UPLOAD=1`** and **`BUNDLE_FILE_NAME`** skip the file-service **REST** upload when the ZIP is already on volume; then install defaults to **v3** only unless **`CAM_REST_API_VERSION`** is set.

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
