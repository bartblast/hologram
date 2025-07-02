alias Hologram.Commons.PLT
alias Hologram.Compiler

Benchee.run(
  %{
    "build_module_beam_path_plt/0" =>
      {fn ->
         Compiler.build_module_beam_path_plt()
       end,
       after_each: fn module_beam_path_plt ->
         PLT.stop(module_beam_path_plt)
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_module_beam_path_plt/0",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
