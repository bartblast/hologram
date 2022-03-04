locals_without_parens = [
  # Hologram.Page
  layout: 1,
  route: 1
]

[
  export: [locals_without_parens: locals_without_parens],
  import_deps: [:phoenix],
  inputs: [
    "*.{ex,exs}",
    "{config,lib}/**/*.{ex,exs}",
    "test/{js,unit}/**/*.{ex,exs}",
    "test/e2e/{config,lib,test}/**/*.{ex,exs}"
  ],
  locals_without_parens: locals_without_parens,
  subdirectories: []
]
