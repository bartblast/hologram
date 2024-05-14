exported_locals_without_parens = [
  # Hologram.Component
  prop: 2,
  prop: 3,

  # Hologram.Page
  layout: 1,
  layout: 2,
  param: 1,
  route: 1
]

test_locals_without_parens = [
  use_module_stub: 1
]

[
  export: [locals_without_parens: exported_locals_without_parens],
  import_deps: [:phoenix],
  inputs: [
    "*.{ex,exs}",
    "{benchmarks,config,lib}/**/*.{ex,exs}",
    "test/elixir/**/*.{ex,exs}"
  ],
  locals_without_parens: exported_locals_without_parens ++ test_locals_without_parens
]
