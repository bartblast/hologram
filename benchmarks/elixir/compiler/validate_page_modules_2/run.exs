alias Hologram.Commons.PLT
alias Hologram.Compiler

Benchee.run(
  %{
    "validate_page_modules/2" => fn {page_modules, module_info_plt} ->
      Compiler.validate_page_modules(page_modules, module_info_plt)
    end
  },
  before_scenario: fn _input ->
    module_info_plt = Compiler.build_module_info_plt!(PLT.start(), nil)

    {Compiler.list_pages(module_info_plt), module_info_plt}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.validate_page_modules/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
