alias Hologram.Reflection

Benchee.run(
  %{
    "is Elixir module" => fn ->
      Reflection.elixir_module?(Bitwise)
    end,
    "is Erlang module" => fn ->
      Reflection.elixir_module?(:elixir_aliases)
    end,
    "is atom" => fn ->
      Reflection.elixir_module?(:abcabcabcabcab)
    end,
    "is not atom" => fn ->
      Reflection.elixir_module?("abcabcabcabcab")
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Reflection.elixir_module?/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
