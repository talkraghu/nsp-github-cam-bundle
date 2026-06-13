# Reference bundle (optional)

Place **`nsp-ne-backup-1.41.0.zip`** here for local or CI workflows that extract the full signed bundle before editing.

- Do **not** commit Nokia-signed production ZIPs or keys to a **public** repository. Use a private repo, Git LFS, or fetch from an internal artifact store in CI.
- A copy of the sample ZIP may live under [`rags-nsp-docs/inno-ideas/cam-northbound/nsp-ne-backup-1.41.0.zip`](../rags-nsp-docs/inno-ideas/cam-northbound/nsp-ne-backup-1.41.0.zip) in the parent `cam` workspace (not guaranteed in every clone).

The default [`source-bundle/`](../source-bundle/) in this repo is a **small builder input** derived from [`build-cam-artifact-bundle-builder`](../build-cam-artifact-bundle-builder) sample content, renamed to **`nsp-ne-backup-1.41.0`** for naming alignment with [`cam-lso-deployer-app`](../cam-lso-deployer-app). It is **not** byte-identical to the full 1.41.0 product bundle.
