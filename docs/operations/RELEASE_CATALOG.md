# Release catalog operation

`assets/release-catalog.json` is the only source from which the installer may
choose an ERPNext runtime. It separates discovery from approval.

## States

| State | Meaning | Installer behavior |
|---|---|---|
| `candidate` | A tag and source configuration discovered from official sources, but not yet pinned and tested. | Must not be offered for installation. |
| `approved` | Images, Compose source, Windows/Docker matrix, backup/restore, Repair, and Reset have been recorded and tested. | May be offered for installation. |
| `retired` | Formerly known version no longer supported by this product. | Must not be offered for new installations. |

## Promotion procedure

1. Start with official Frappe Docker source and record its commit SHA.
2. Resolve the multi-architecture manifest digest for `frappe/erpnext`,
   `mariadb`, and `redis` using Docker Registry metadata.
3. Record those digests and the precise Docker Desktop/Windows/WSL versions.
4. Generate the local Compose bundle and run the contract test in
   `docs/architecture/COMPOSE_INTEGRATION.md`.
5. Record test evidence, set the entry to `approved`, and update the catalog
   status only after all intended installable entries are approved.
6. Run `tools/ReleaseCatalog/Test-ReleaseCatalog.ps1` before committing.

## Prohibitions

- Do not use `latest` tags.
- Do not promote from a moving tag without recording a digest.
- Do not edit a previously approved entry in place; add a new approval record
  or retire the old entry so installed systems remain traceable.
