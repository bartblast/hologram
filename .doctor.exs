%Doctor.Config{
  exception_moduledoc_required: true,
  # Hologram.Page is ignored because there are false positives.
  ignore_modules: [Hologram.Page],
  ignore_paths: [~r(^test/*)],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 100,
  min_overall_moduledoc_coverage: 0,
  min_overall_spec_coverage: 100,
  struct_type_spec_required: true
}
