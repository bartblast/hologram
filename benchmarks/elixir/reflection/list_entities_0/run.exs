alias Hologram.Reflection

# What a listing of the entity types from the beams costs: every app's ebin directory is globbed
# and the export table of every beam it holds is read, concurrently. A compile lists the entity
# types from its module info PLT and pays none of it. Warm: the code server already has the paths
# and the filesystem has the directory listings cached.
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
