# nsp-github-cam-bundle

**Purpose:** Automate building the **`nsp-ne-backup`** CAM artifact bundle (Go builder in-repo) and driving **lab** lifecycle with **GitHub Actions** or local scripts: **repack**, optional **upload** to NSP file service, **install** or **uninstall** via **CAM REST**. Intended for the **`cam-lso-deployer-app`** pilot and **non-production** clusters only.

**Detailed reference:** [detailed-readme.md](./detailed-readme.md) (layout table, file-service vs CAM, TLS, Postman, troubleshooting, full CI notes).

## High-level architecture

1. **Inputs**  
   [`source-bundle/`](./source-bundle/) holds `metadata.json` and `content/` in the shape expected by the vendored [`artifact-bundle-builder`](./builder/VENDOR.md).

2. **Build**  
   [`scripts/repack.sh`](./scripts/repack.sh) compiles the builder and writes **`dist/*.zip`** (default unsigned).

3. **Lab automation**  
   - **File service (optional HTTP path):** the bundle ZIP must end up under **`/nokia/nsp/cam/artifacts/bundle/`** on NSP storage. Scripts can **`POST .../uploadFile`** or you can copy the file on the volume (see detailed doc).  
   - **CAM:** batch **install** and **uninstall** are JSON **`{"bundles":["<zip-file-name>"]}`** against **`/cam/rest/api/<v>/artifactBundle/...`** (exact paths and version fallback are in [detailed-readme.md](./detailed-readme.md) and [`cam-server-app`](../cam-server-app/) controllers).

4. **CI**  
   **GitHub-hosted** workflows can **repack** and publish artifacts. **Deploy / uninstall** workflows target a **self-hosted Windows** runner inside the lab/VPN so `curl` can reach **`https://<lab>`** (hosted runners cannot).

```text
  source-bundle + builder --repack--> dist/*.zip
                           |
            +--------------+--------------+
            v                             v
   (optional) file service REST    CAM REST install / uninstall
   upload to bundle dir            (JSON bundle names only)
```

## How to use

### Prerequisites

- **Go 1.17+** for local repack (CI uses 1.22).
- **Lab:** `NSP_BASE_URL`, JWT as **`CAM_TOKEN`** (no `Bearer ` prefix in `.env`). Copy [`.env.example`](./.env.example) to **`.env`** (gitignored).

### Build locally

```bash
./scripts/repack.sh
ls -la dist/
```

### Install on the lab (from your machine)

```bash
cp .env.example .env
# edit .env: NSP_BASE_URL, CAM_TOKEN
./scripts/repack.sh
./scripts/upload-and-install.sh
```

Script reads **`.env`** automatically. For **install-only** after manual copy to the bundle directory, **`SKIP_FILE_SERVICE_UPLOAD=1`** and **`BUNDLE_FILE_NAME`** -- see [detailed-readme.md](./detailed-readme.md).

### Uninstall on the lab

```bash
export BUNDLE_FILE_NAME=nsp-ne-backup-1.41.0.zip
./scripts/uninstall-bundle.sh
```

### GitHub Actions (summary)

| Workflow | Role |
| -------- | ---- |
| [`build-repack-nsp-ne-backup.yml`](./.github/workflows/build-repack-nsp-ne-backup.yml) | Repack on push/PR; upload **`dist/*.zip`** artifact. |
| [`deploy-nsp-cam-bundle.yml`](./.github/workflows/deploy-nsp-cam-bundle.yml) | Manual: repack + **`upload-and-install.sh`** on **self-hosted Windows**. |
| [`install-nsp-cam-bundle-v3-only.yml`](./.github/workflows/install-nsp-cam-bundle-v3-only.yml) | Manual: install preloaded bundle by name via **v3 install** only. |
| [`uninstall-nsp-cam-bundle.yml`](./.github/workflows/uninstall-nsp-cam-bundle.yml) | Manual: **`uninstall-bundle.sh`** with workflow input **`bundle_file_name`**. |
| [`list-nsp-cam-bundles.yml`](./.github/workflows/list-nsp-cam-bundles.yml) | Manual: **`list-bundles.sh`** to list all CAM bundles via REST. |

Secrets: **`NSP_BASE_URL`**, **`CAM_TOKEN`**. Optional repo **variables** and TLS behavior are documented in [detailed-readme.md](./detailed-readme.md).

```bash
gh workflow run deploy-nsp-cam-bundle.yml --ref main
gh workflow run install-nsp-cam-bundle-v3-only.yml --ref main -f bundle_file_name=nsp-ne-backup-1.41.0.zip
gh workflow run uninstall-nsp-cam-bundle.yml --ref main -f bundle_file_name=nsp-ne-backup-1.41.0.zip
gh workflow run list-nsp-cam-bundles.yml --ref main
```

## Related documentation

- [detailed-readme.md](./detailed-readme.md) -- long-form operational guide  
- [Northbound implementation plan](../rags-nsp-docs/inno-ideas/cam-northbound/cam-northbound-github-integration-implementation-plan.md)  
- [ARTIFACTS_AND_BUNDLES.md](../rags-nsp-docs/cam-docs/ARTIFACTS_AND_BUNDLES.md)  
- [ARCH_NSPF-264170 CAM API hardening (v3)](../rags-nsp-docs/cam-docs/camapi-v3/ARCH_NSPF-264170_CAM_API_Hardening_v3.md)

**Security:** Never commit JWTs or PATs. Rotate any token that leaked into chat or git history.
