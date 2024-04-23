alias Hologram.Commons.FileUtils
alias Hologram.Commons.PLT
alias Hologram.Commons.Reflection
alias Hologram.Compiler

Benchee.run(
  %{
    "no load" =>
      {fn build_dir ->
         Compiler.maybe_load_module_beam_path_plt(build_dir)
       end,
       before_scenario: fn _input ->
         build_dir =
           Path.join([Reflection.tmp_dir(), "compiler", "maybe_load_module_beam_path_plt_no_load"])

         FileUtils.recreate_dir(build_dir)

         build_dir
       end},
    "do load" =>
      {fn build_dir ->
         Compiler.maybe_load_module_beam_path_plt(build_dir)
       end,
       before_scenario: fn _input ->
         build_dir =
           Path.join([Reflection.tmp_dir(), "compiler", "maybe_load_module_beam_path_plt_do_load"])

         plt = Compiler.build_module_beam_path_plt()

         dump_path = Path.join(build_dir, "module_beam_path.plt")
         PLT.dump(plt, dump_path)

         build_dir
       end}
  },
  after_each: fn {plt, _dump_path} ->
    PLT.stop(plt)
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "maybe_load_module_beam_path_plt/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
