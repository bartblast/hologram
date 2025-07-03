alias Hologram.Reflection

Benchee.run(
  %{
    "has_function?/3" => fn ->
      Reflection.has_function?(Map, :get, 3)
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Reflection.has_function?/3", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
