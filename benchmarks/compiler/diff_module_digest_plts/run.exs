alias Hologram.Commons.CryptographicUtils
alias Hologram.Commons.PLT
alias Hologram.Commons.Reflection
alias Hologram.Commons.TaskUtils
alias Hologram.Compiler

module_beam_path_plt = PLT.start()

Reflection.list_elixir_modules()
|> TaskUtils.async_many(fn module ->
  beam_path = :code.which(module)
  PLT.put(module_beam_path_plt, module, beam_path)
end)
|> Task.await_many(:infinity)

module_digest_plt = Compiler.build_module_digest_plt!(module_beam_path_plt)

empty_module_digest_plt = PLT.start()

Benchee.run(
  %{
    "no module changes" => fn ->
      Compiler.diff_module_digest_plts(module_digest_plt, module_digest_plt)
    end,
    "all modules added" => fn ->
      Compiler.diff_module_digest_plts(empty_module_digest_plt, module_digest_plt)
    end,
    "all modules removed" => fn ->
      Compiler.diff_module_digest_plts(module_digest_plt, empty_module_digest_plt)
    end,
    "all modules updated" =>
      {fn all_updated_module_digest_plt ->
         Compiler.diff_module_digest_plts(module_digest_plt, all_updated_module_digest_plt)
       end,
       before_scenario: fn _input ->
         all_updated_module_digest_plt_items =
           module_digest_plt
           |> PLT.get_all()
           |> Enum.map(fn {key, value} ->
             {key, CryptographicUtils.digest(value, :sha256, :binary)}
           end)

         PLT.start(items: all_updated_module_digest_plt_items)
       end},
    "1/3 added, 1/3 removed, 1/3 updated" => {
      fn {old_module_digest_plt, new_module_digest_plt} ->
        Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
      end,
      before_scenario: fn _input ->
        module_digests = PLT.get_all(module_digest_plt)
        count = Enum.count(module_digests)
        chunk_size = Integer.floor_div(count, 3)

        [_removed_module_digests, added_module_digests, updated_module_digests] =
          case Enum.chunk_every(module_digests, chunk_size) do
            [chunk_1, chunk_2, chunk_3, chunk_4] ->
              [chunk_1, chunk_2, chunk_3 ++ chunk_4]

            chunks ->
              chunks
          end

        old_module_digests =
          module_digests
          |> Map.drop(Enum.map(added_module_digests, fn {key, _value} -> key end))
          |> Map.to_list()

        old_module_digest_plt = PLT.start(items: old_module_digests)

        new_module_digests =
          updated_module_digests
          |> Enum.map(fn {key, value} ->
            {key, CryptographicUtils.digest(value, :sha256, :binary)}
          end)
          |> Kernel.++(added_module_digests)

        new_module_digest_plt = PLT.start(items: new_module_digests)

        {old_module_digest_plt, new_module_digest_plt}
      end
    }
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "diff_module_digest_plts/2", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
