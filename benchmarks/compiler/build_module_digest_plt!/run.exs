alias Hologram.Commons.PLT
alias Hologram.Commons.Reflection
alias Hologram.Commons.TaskUtils
alias Hologram.Compiler

# Setup "no cache" case

no_cache_module_beam_path_plt = PLT.start()

# Setup "has cache" case

has_cache_module_beam_path_plt = PLT.start()

Reflection.list_elixir_modules()
|> TaskUtils.async_many(fn module ->
  beam_path = :code.which(module)
  PLT.put(has_cache_module_beam_path_plt, module, beam_path)
end)
|> Task.await_many(:infinity)

Benchee.run(
  %{
    "no cache" =>
      {fn ->
         Compiler.build_module_digest_plt!(no_cache_module_beam_path_plt)
       end,
       after_each: fn _module_digest_plt ->
         PLT.reset(no_cache_module_beam_path_plt)
       end},
    "has cache" => fn ->
      Compiler.build_module_digest_plt!(has_cache_module_beam_path_plt)
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "maybe_load_module_beam_path_plt/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
