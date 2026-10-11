alias Hologram.Commons.FileUtils
alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Reflection

# With no previous dump the old PLT is never read, so one empty PLT serves every iteration of
# that scenario; the reuse scenario shares one loaded PLT the same way. Each scenario stops its
# shared PLT when it is done, and every returned PLT is stopped after each iteration.
Benchee.run(
  %{
    "no previous dump (every beam read)" =>
      {fn old_plt ->
         Compiler.build_module_info_plt!(old_plt, nil)
       end,
       before_scenario: fn _input ->
         PLT.start()
       end,
       after_each: fn module_info_plt ->
         PLT.stop(module_info_plt)
       end,
       after_scenario: fn old_plt ->
         PLT.stop(old_plt)
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

         built_plt = Compiler.build_module_info_plt!(PLT.start(), nil)
         PLT.dump(built_plt, dump_path)
         PLT.stop(built_plt)

         # Every beam predates the dump; a cutoff well after the dump makes them all reusable.
         {old_plt, ^dump_path, dumped_at} = Compiler.maybe_load_module_info_plt(build_dir)

         {old_plt, dumped_at + 60}
       end,
       after_each: fn module_info_plt ->
         PLT.stop(module_info_plt)
       end,
       after_scenario: fn {old_plt, _dumped_at} ->
         PLT.stop(old_plt)
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
