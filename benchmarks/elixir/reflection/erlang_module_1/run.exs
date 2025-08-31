alias Hologram.Reflection

Benchee.run(
  %{
    "is Elixir module" => fn ->
      Reflection.erlang_module?(Bitwise)
    end,
    "is Erlang module" => fn ->
      Reflection.erlang_module?(:elixir_aliases)
    end,
    "is atom" => fn ->
      Reflection.erlang_module?(:abcabcabcabcab)
    end,
    "is not atom" => fn ->
      Reflection.erlang_module?("abcabcabcabcab")
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Reflection.erlang_module?/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
