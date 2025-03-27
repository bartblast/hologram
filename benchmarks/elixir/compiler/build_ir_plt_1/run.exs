alias Hologram.Commons.PLT
alias Hologram.Compiler

Benchee.run(
  %{
    "build_ir_plt/1" =>
      {fn module_beam_path_plt ->
         Compiler.build_ir_plt(module_beam_path_plt)
       end,
       before_scenario: fn _input ->
         Compiler.build_module_beam_path_plt()
       end,
       after_each: fn ir_plt ->
         PLT.stop(ir_plt)
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_ir_plt/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
