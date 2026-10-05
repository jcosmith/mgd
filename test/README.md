# Test assets

## `assets/matillion-repo`

A Matillion ETL for Azure Synapse repository in the layout Matillion's Git
integration writes:

```
.build_version                  {"version":"1.75.8","environment":"synapse"}
version                         {"description":""}
ROOT/Sales/Orchestration/*.ORCHESTRATION
ROOT/Sales/Transformation/*.TRANSFORMATION
ROOT/Shared/weekly_rollup.ORCHESTRATION
```

The file format (minified single-line JSON, `job`/`info` objects, slot-keyed
parameters, connector maps, `notes`, `variables`, `grids`) was modelled on public
Matillion ETL repositories on GitHub. The content is invented for testing, and
the `implementationID`s come from `.docs/implementation_id_to_type.json`.

History:

```
* 8dcd57a (feature/eu-orders) Log load failures                  2026-10-04
* 761026c EU region split                                        2026-10-02
|   daily_load: remove step, rename, SQL change, move; t_orders_enrich: grid rows;
|   delete t_legacy_customers; add init_env
| * 9c55e48 (main, HEAD) Update Matillion ETL build version      2026-10-03  (.build_version only)
|/
* 256fd43 (tag: v1.0) Tidy weekly_rollup canvas                  2026-09-02  (layout-only change)
| * da02603 (hotfix/load-timeout) Increase ERP login timeout     2025-12-01  (stale branch)
|/
* 3cca1dd Initial export of Sales project                        2025-11-03
```

`hotfix/load-timeout` has not been touched for months, so the app's default
"active in the last 6 months" branch filter hides it.

### Why `.gitted` instead of `.git`

A folder containing `.git` cannot be committed into another repository. Its contents
would be lost, and it would be recorded as a submodule. The fixture's Git database
is therefore stored as `.gitted` (the libgit2 test-fixture convention).
`GitCliSource.open` uses `.git` when present and falls back to `.gitted`.
`.gitattributes` marks the folder `-text`, so line-ending conversion cannot alter it.

### Rebuilding

```sh
dart run test/tools/build_matillion_repo.dart
```

Commit dates and identities are fixed, so the rebuilt repository has the same
commit SHAs.
