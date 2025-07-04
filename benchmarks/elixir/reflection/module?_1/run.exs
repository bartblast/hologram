alias Hologram.Reflection

Benchee.run(
  %{
    "is Erlang module" => fn ->
      Reflection.module?(:elixir_aliases)
    end,
    "is Elixir module" => fn ->
      Reflection.module?(Hologram.Reflection)
    end,
    "is atom" => fn ->
      Reflection.module?(:abc)
    end,
    "is not atom" => fn ->
      Reflection.module?("abc")
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Reflection.module?/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
