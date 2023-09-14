locals_without_parens = [
  # Hologram.Page
  layout: 1,
  layout: 2,
  param: 1,
  route: 1,

  # Hologram.Runtime.Templatable
  prop: 2,
  prop: 3
]

[
  export: [locals_without_parens: locals_without_parens],
  inputs: [
    "*.{ex,exs}",
    "{config,lib}/**/*.{ex,exs}",
    "test/elixir/*.{ex,exs}",
    "test/elixir/{fixtures,hologram,mix,support}/**/*.{ex,exs}"
  ],
  locals_without_parens: locals_without_parens
]
