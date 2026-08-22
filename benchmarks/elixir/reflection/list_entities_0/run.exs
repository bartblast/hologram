alias Hologram.Reflection

# The sweep every builder of the compile pays once per build, and the one the query extractor used
# to pay once per replayed variant - every app's ebin directory is globbed and every module it
# holds is asked whether it is an entity type. Warm: the code server already has the paths and the
# filesystem has the directory listings cached, which is the state a build runs in.
Benchee.run(
  %{
    "list_entities/0" => fn ->
      Reflection.list_entities()
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Reflection.list_entities/0", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
