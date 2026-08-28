exported_locals_without_parens = [
  # Hologram.Component
  prop: 2,
  prop: 3,

  # Hologram.Entity
  allow: 1,
  allow: 2,
  attribute: 2,
  attribute: 3,
  relationship: 2,
  relationship: 3,
  role: 1,
  role: 2,

  # Hologram.JS
  js_import: 1,
  js_import: 2,

  # Hologram.Middleware.Builder
  middleware: 1,
  middleware: 2,

  # Hologram.Migration
  add_attribute: 2,
  add_attribute: 3,
  add_enum_value: 2,
  add_enum_value: 3,
  add_relationship: 2,
  add_relationship: 3,
  add_role: 1,
  add_role: 2,
  change_attribute: 2,
  change_relationship: 2,
  change_role: 2,
  create_entity: 1,
  delete_attribute: 1,
  delete_entity: 1,
  delete_enum_value: 2,
  delete_relationship: 1,
  delete_role: 1,
  designate_user_entity: 1,
  rename_attribute: 2,
  rename_entity: 2,
  rename_enum_value: 3,
  rename_relationship: 2,
  rename_role: 2,
  reorder_enum_values: 2,
  resolve!: 1,
  resolve!: 2,

  # Hologram.Page
  layout: 1,
  layout: 2,
  param: 2,
  param: 3,
  route: 1,

  # Hologram.Policy
  policy: 1
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
        "{benchmarks,config,lib,scripts}/**/*.{ex,exs}",
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
