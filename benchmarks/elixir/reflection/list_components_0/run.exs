alias Hologram.Reflection

Benchee.run(
  %{
    "list_components/0" => fn ->
      Reflection.list_components()
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Reflection.list_components/0", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
