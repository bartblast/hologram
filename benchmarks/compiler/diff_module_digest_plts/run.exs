alias Hologram.Benchmarks
alias Hologram.Commons.CryptographicUtils
alias Hologram.Commons.PLT
alias Hologram.Compiler

module_beam_path_plt = Benchmarks.build_module_beam_path_plt()

Benchee.run(
  %{
    "no module changes" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         old_module_digest_plt =
           new_module_digest_plt = Compiler.build_module_digest_plt!(module_beam_path_plt)

         {old_module_digest_plt, new_module_digest_plt}
       end},
    "all modules added" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         old_module_digest_plt = PLT.start()
         new_module_digest_plt = Compiler.build_module_digest_plt!(module_beam_path_plt)
         {old_module_digest_plt, new_module_digest_plt}
       end},
    "all modules removed" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         old_module_digest_plt = Compiler.build_module_digest_plt!(module_beam_path_plt)
         new_module_digest_plt = PLT.start()
         {old_module_digest_plt, new_module_digest_plt}
       end},
    "all modules updated" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         old_module_digest_plt = Compiler.build_module_digest_plt!(module_beam_path_plt)

         new_module_digest_plt_items =
           old_module_digest_plt
           |> PLT.get_all()
           |> Enum.map(fn {key, value} ->
             {key, CryptographicUtils.digest(value, :sha256, :binary)}
           end)

         new_module_digest_plt = PLT.start(items: new_module_digest_plt_items)

         {old_module_digest_plt, new_module_digest_plt}
       end},
    "1/3 added, 1/3 removed, 1/3 updated" => {
      fn {old_module_digest_plt, new_module_digest_plt} ->
        Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
      end,
      before_scenario: fn _input ->
        module_digests =
          module_beam_path_plt
          |> Compiler.build_module_digest_plt!()
          |> PLT.get_all()

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
