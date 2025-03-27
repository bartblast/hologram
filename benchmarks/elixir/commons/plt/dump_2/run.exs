alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Reflection

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
             "dump_2",
             Reflection.module_beam_path_plt_dump_file_name()
           ])

         PLT.dump(module_beam_path_plt, dump_path)

         {module_beam_path_plt, dump_path}
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Commons.PLT.dump/2", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
