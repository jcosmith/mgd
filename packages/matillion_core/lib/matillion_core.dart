/// Matillion ETL job model, component registry, semantic diff and the
/// read-only repository port. Contains no `dart:io`, so it runs in the browser.
library;

export 'src/diff/job_diff.dart';
export 'src/diff/job_differ.dart';
export 'src/diff/sequence_diff.dart';
export 'src/diff/summary.dart';
export 'src/model/job.dart';
export 'src/model/values.dart';
export 'src/parser/build_info.dart';
export 'src/parser/job_parser.dart';
export 'src/print/canonical_json.dart';
export 'src/registry/component_meta.dart';
export 'src/registry/component_registry.dart';
export 'src/registry/implementation_ids.g.dart';
export 'src/registry/variants.dart';
export 'src/repo/http_repository_source.dart';
export 'src/repo/repository_browser.dart';
export 'src/repo/repository_source.dart';
export 'src/service/compare_service.dart';
