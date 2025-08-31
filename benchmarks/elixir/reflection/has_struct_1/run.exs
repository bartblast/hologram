alias Hologram.Reflection

Benchee.run(
  %{
    "has_struct?/1" => fn ->
      Reflection.has_struct?(Hologram.Component)
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Reflection.has_struct?/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
