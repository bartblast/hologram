%Doctor.Config{
  # TODO: remove Hologram.Compiler.PatternMatching
  ignore_modules: [Hologram.Compiler.PatternMatching],
  ignore_paths: [~r(^test/*)],
  min_overall_moduledoc_coverage: 0
}
