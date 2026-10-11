alias Hologram.Commons.PLT
alias Hologram.Compiler

Benchee.run(
  %{
    "build_module_metadata/1" => fn module_info_plt ->
      Compiler.build_module_metadata(module_info_plt)
    end
  },
  before_scenario: fn _input ->
    Compiler.build_module_info_plt!(PLT.start(), nil)
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_module_metadata/1",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
