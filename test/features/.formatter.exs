[
  import_deps: [:hologram, :phoenix],
  inputs: ["*.{ex,exs}", "{app,config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: [
    assert_client_error: 4,
    assert_js_error: 3
  ]
]
