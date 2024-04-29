alias Hologram.Commons.PLT
alias Hologram.Commons.Reflection
alias Hologram.Compiler

Benchee.run(
  %{
    "module BEAM path PLT" =>
      {fn {module_beam_path_plt, dump_path} ->
         PLT.dump(module_beam_path_plt, dump_path)
       end,
       before_scenario: fn _input ->
         module_beam_path_plt = Compiler.build_module_beam_path_plt()

         dump_path =
           Path.join([
             Reflection.tmp_dir(),
             "benchmarks",
             "commons",
             "plt",
             "dump",
             "module_beam_path.plt"
           ])

         PLT.dump(module_beam_path_plt, dump_path)

         {module_beam_path_plt, dump_path}
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "PLT.dump/2", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
