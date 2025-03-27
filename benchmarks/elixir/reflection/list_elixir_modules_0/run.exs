alias Hologram.Reflection

Benchee.run(
  %{
    "list_elixir_modules/0" => fn ->
      Reflection.list_elixir_modules()
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Reflection.list_elixir_modules/0",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
