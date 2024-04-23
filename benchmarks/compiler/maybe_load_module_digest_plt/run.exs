alias Hologram.Commons.FileUtils
alias Hologram.Commons.PLT
alias Hologram.Commons.Reflection
alias Hologram.Compiler

Benchee.run(
  %{
    "no load" =>
      {fn build_dir ->
         Compiler.maybe_load_module_digest_plt(build_dir)
       end,
       before_scenario: fn _input ->
         build_dir =
           Path.join([Reflection.tmp_dir(), "compiler", "maybe_load_module_digest_plt_no_load"])

         FileUtils.recreate_dir(build_dir)

         build_dir
       end},
    "do load" =>
      {fn build_dir ->
         Compiler.maybe_load_module_digest_plt(build_dir)
       end,
       before_scenario: fn _input ->
         build_dir =
           Path.join([Reflection.tmp_dir(), "compiler", "maybe_load_module_digest_plt_do_load"])

         module_beam_path_plt = Compiler.build_module_beam_path_plt()
         module_digest_plt = Compiler.build_module_digest_plt!(module_beam_path_plt)

         module_digest_plt_dump_path = Path.join(build_dir, "module_digest.plt")
         PLT.dump(module_digest_plt, module_digest_plt_dump_path)

         build_dir
       end}
  },
  after_each: fn {module_digest_plt, _module_digest_plt_dump_path} ->
    PLT.stop(module_digest_plt)
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "maybe_load_module_digest_plt/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
