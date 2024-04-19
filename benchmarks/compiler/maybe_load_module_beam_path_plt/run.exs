alias Hologram.Commons.FileUtils
alias Hologram.Commons.PLT
alias Hologram.Commons.Reflection
alias Hologram.Commons.TaskUtils
alias Hologram.Compiler

# Setup "no load" case

no_load_build_dir =
  Path.join([Reflection.tmp_dir(), "compiler", "maybe_load_module_beam_path_plt_no_load"])

FileUtils.recreate_dir(no_load_build_dir)

# Setup "do load" case

do_load_build_dir =
  Path.join([Reflection.tmp_dir(), "compiler", "maybe_load_module_beam_path_plt_do_load"])

module_beam_path_plt = PLT.start()

Reflection.list_elixir_modules()
|> TaskUtils.async_many(fn module ->
  beam_path = :code.which(module)
  PLT.put(module_beam_path_plt, module, beam_path)
end)
|> Task.await_many(:infinity)

module_beam_path_plt_dump_path = Path.join(do_load_build_dir, "module_beam_path.plt")
PLT.dump(module_beam_path_plt, module_beam_path_plt_dump_path)

Benchee.run(
  %{
    "no load" => fn ->
      Compiler.maybe_load_module_beam_path_plt(no_load_build_dir)
    end,
    "do load" => fn ->
      Compiler.maybe_load_module_beam_path_plt(do_load_build_dir)
    end
  },
  after_each: fn {module_beam_path_plt, _module_beam_path_plt_dump_path} ->
    PLT.stop(module_beam_path_plt)
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "maybe_load_module_beam_path_plt/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
