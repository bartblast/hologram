alias Hologram.Commons.PLT
alias Hologram.Compiler

Benchee.run(
  %{
    "build_ir_plt/0" =>
      {fn ->
         Compiler.build_ir_plt()
       end,
       after_each: fn ir_plt ->
         PLT.stop(ir_plt)
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_ir_plt/0", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
