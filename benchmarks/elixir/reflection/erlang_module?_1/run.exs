alias Hologram.Reflection

Benchee.run(
  %{
    "is Erlang module" => fn ->
      Reflection.erlang_module?(:elixir_aliases)
    end,
    "is Elixir module" => fn ->
      Reflection.erlang_module?(Hologram.Reflection)
    end,
    "is atom" => fn ->
      Reflection.erlang_module?(:abc)
    end,
    "is not atom" => fn ->
      Reflection.erlang_module?("abc")
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Reflection.erlang_module?/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
