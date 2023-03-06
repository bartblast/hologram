locals_without_parens = [
  # Hologram.Page
  layout: 1,
  route: 1
]

# module fixture file is ignored, to be able to test cases when there are no parenthesis in aliased calls
inputs =
  [
    "*.{ex,exs}",
    "{config,lib}/**/*.{ex,exs}",
    "test/{js,unit}/**/*.{ex,exs}",
    "test/e2e/{config,lib,test}/**/*.{ex,exs}"
  ]
  |> Enum.flat_map(&Path.wildcard(&1, match_dot: true))
  |> Kernel.--(["test/unit/fixtures/compiler/transformer/module_1.ex"])

[
  export: [locals_without_parens: locals_without_parens],
  import_deps: [:phoenix],
  inputs: inputs,
  locals_without_parens: locals_without_parens,
  subdirectories: []
]
