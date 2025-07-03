alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Reflection

Benchee.run(
  %{
    "IR PLT" =>
      {fn {ir_plt, dump_path} ->
         PLT.dump(ir_plt, dump_path)
       end,
       before_scenario: fn _input ->
         ir_plt = Compiler.build_ir_plt()

         dump_path =
           Path.join([
             Reflection.tmp_dir(),
             "benchmarks",
             "commons",
             "plt",
             "dump_2",
             Reflection.ir_plt_dump_file_name()
           ])

         PLT.dump(ir_plt, dump_path)

         {ir_plt, dump_path}
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Commons.PLT.dump/2", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
