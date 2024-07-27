exported_locals_without_parens = [
  # Hologram.Component
  prop: 2,
  prop: 3,

  # Hologram.Page
  layout: 1,
  layout: 2,
  param: 2,
  param: 3,
  route: 1
]

test_locals_without_parens = [
  assert_error: 3,
  use_module_stub: 1
]

[
  export: [locals_without_parens: exported_locals_without_parens],
  import_deps: [:phoenix],
  inputs:
    Enum.flat_map(
      [
        "*.{ex,exs}",
        "{benchmarks,config,lib}/**/*.{ex,exs}",
        "test/elixir/**/*.{ex,exs}"
      ],
      &Path.wildcard(&1, match_dot: true)
    ) --
      [
        "test/elixir/support/fixtures/compiler/transformer/module_96.ex",
        "test/elixir/support/fixtures/compiler/transformer/module_101.ex"
      ],
  locals_without_parens: exported_locals_without_parens ++ test_locals_without_parens
]
