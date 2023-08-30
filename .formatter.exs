locals_without_parens = [
  # Hologram.Page
  layout: 1,
  layout: 2,
  param: 1,
  route: 1,

  # Hologram.Runtime.Templatable
  prop: 1
]

[
  export: [locals_without_parens: locals_without_parens],
  inputs: [
    "*.{ex,exs}",
    "{config,lib}/**/*.{ex,exs}",
    "test/elixir/**/*.{ex,exs}"
  ],
  locals_without_parens: locals_without_parens
]
