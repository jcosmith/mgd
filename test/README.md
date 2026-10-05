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
* 41443ae (feature/eu-orders) Log load failures
* 670a5cd EU region split          daily_load: remove step, rename, SQL change, move;
|                                  t_orders_enrich: grid rows; delete t_legacy_customers; add init_env
| * 8d852d1 (main, HEAD) Update Matillion ETL build version     (.build_version only)
|/
* dbab864 (tag: v1.0) Tidy weekly_rollup canvas                  (layout-only change)
* 28fea84 Initial export of Sales project
```

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
