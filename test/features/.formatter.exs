[
  import_deps: [:hologram, :phoenix],
  inputs: ["*.{ex,exs}", "{app,config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: [
    assert_js_error: 2
  ]
]
