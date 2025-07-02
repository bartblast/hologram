alias Hologram.Reflection

Benchee.run(
  %{
    "list_protocol_implementations/1" => fn ->
      Reflection.list_protocol_implementations(String.Chars)
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Reflection.list_protocol_implementations/1",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
