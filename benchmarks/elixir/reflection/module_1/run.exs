alias Hologram.Reflection

Benchee.run(
  %{
    "is Elixir module" => fn ->
      Reflection.module?(Bitwise)
    end,
    "is Erlang module" => fn ->
      Reflection.module?(:elixir_aliases)
    end,
    "is atom" => fn ->
      Reflection.module?(:abcabcabcabcab)
    end,
    "is not atom" => fn ->
      Reflection.module?("abcabcabcabcab")
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Reflection.module?/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
