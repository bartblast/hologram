alias Hologram.Commons.FileUtils
alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Reflection

Benchee.run(
  %{
    "no previous dump (every beam read)" =>
      {fn ->
         Compiler.build_module_info_plt!(PLT.start(), nil)
       end,
       after_each: fn module_info_plt ->
         PLT.stop(module_info_plt)
       end},
    "previous dump, nothing changed (every entry reused)" =>
      {fn {old_plt, dumped_at} ->
         Compiler.build_module_info_plt!(old_plt, dumped_at)
       end,
       before_scenario: fn _input ->
         build_dir =
           Path.join([
             Reflection.tmp_dir(),
             "benchmarks",
             "compiler",
             "build_module_info_plt!_2"
           ])

         FileUtils.recreate_dir(build_dir)

         dump_path = Path.join(build_dir, Reflection.module_info_plt_dump_file_name())

         PLT.start()
         |> Compiler.build_module_info_plt!(nil)
         |> PLT.dump(dump_path)

         # Every beam predates the dump; a cutoff well after the dump makes them all reusable.
         {old_plt, ^dump_path, dumped_at} = Compiler.maybe_load_module_info_plt(build_dir)

         {old_plt, dumped_at + 60}
       end,
       after_each: fn module_info_plt ->
         PLT.stop(module_info_plt)
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_module_info_plt!/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
