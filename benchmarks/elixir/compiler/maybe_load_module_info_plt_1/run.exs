alias Hologram.Commons.FileUtils
alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Reflection

Benchee.run(
  %{
    "no load" =>
      {fn build_dir ->
         Compiler.maybe_load_module_info_plt(build_dir)
       end,
       before_scenario: fn _input ->
         build_dir =
           Path.join([
             Reflection.tmp_dir(),
             "benchmarks",
             "compiler",
             "maybe_load_module_info_plt_1"
           ])

         FileUtils.recreate_dir(build_dir)

         build_dir
       end},
    "do load" =>
      {fn build_dir ->
         Compiler.maybe_load_module_info_plt(build_dir)
       end,
       before_scenario: fn _input ->
         build_dir =
           Path.join([
             Reflection.tmp_dir(),
             "benchmarks",
             "compiler",
             "maybe_load_module_info_plt_1"
           ])

         module_info_plt = Compiler.build_module_info_plt!(PLT.start(), nil)

         module_info_plt_dump_path =
           Path.join(build_dir, Reflection.module_info_plt_dump_file_name())

         PLT.dump(module_info_plt, module_info_plt_dump_path)

         build_dir
       end}
  },
  after_each: fn {module_info_plt, _module_info_plt_dump_path, _dumped_at} ->
    PLT.stop(module_info_plt)
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.maybe_load_module_info_plt/1",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
