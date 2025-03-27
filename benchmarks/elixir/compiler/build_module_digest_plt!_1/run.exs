alias Hologram.Commons.PLT
alias Hologram.Compiler

Benchee.run(
  %{
    "no cache" =>
      {fn module_beam_path_plt ->
         {module_beam_path_plt, Compiler.build_module_digest_plt!(module_beam_path_plt)}
       end,
       before_each: fn _input ->
         PLT.start()
       end,
       after_each: fn {module_beam_path_plt, module_digest_plt} ->
         PLT.stop(module_beam_path_plt)
         PLT.stop(module_digest_plt)
       end},
    "has cache" =>
      {fn module_beam_path_plt ->
         Compiler.build_module_digest_plt!(module_beam_path_plt)
       end,
       before_scenario: fn _input ->
         Compiler.build_module_beam_path_plt()
       end,
       after_each: fn module_digest_plt ->
         PLT.stop(module_digest_plt)
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_module_digest_plt!/1",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
