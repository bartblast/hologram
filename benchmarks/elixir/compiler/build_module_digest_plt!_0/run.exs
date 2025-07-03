alias Hologram.Commons.PLT
alias Hologram.Compiler

Benchee.run(
  %{
    "build_module_digest_plt!/0" =>
      {fn ->
         Compiler.build_module_digest_plt!()
       end,
       after_each: fn module_digest_plt ->
         PLT.stop(module_digest_plt)
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_module_digest_plt!/0",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
