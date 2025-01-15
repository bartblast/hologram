%Doctor.Config{
  exception_moduledoc_required: true,
  # False positives are reported for these modules:
  ignore_modules: [
    Hologram.Component,
    Hologram.Layout,
    Hologram.Page
  ],
  ignore_paths: [~r(^benchmarks/*), ~r(^lib/libgraph/*), ~r(^test/*)],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 100,
  min_overall_moduledoc_coverage: 0,
  min_overall_spec_coverage: 100,
  struct_type_spec_required: true
}
