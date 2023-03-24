%{
  configs: [
    %{
      name: "default",
      files: %{
        # You can give explicit globs or simply directories.
        # In the latter case `**/*.{ex,exs}` will be used.
        # TODO: add E2E test app dirs
        included: ["*.{ex,exs}", "config/", "lib/", "priv/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      strict: true,
      checks: %{
        disabled: [
          {Credo.Check.Design.TagTODO, []},
          {Credo.Check.Readability.ModuleDoc, []}
        ]
      }
    }
  ]
}
