alias Hologram.Benchmarks
alias Hologram.Compiler

Benchee.run(
  %{
    "no module changes" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         module_beam_path_plt = Compiler.build_module_beam_path_plt()
         module_digest_plt = Compiler.build_module_digest_plt!(module_beam_path_plt)
         {module_digest_plt, module_digest_plt}
       end},
    "all modules added" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         Benchmarks.generate_module_digest_plts(100, 0, 0)
       end},
    "all modules removed" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         Benchmarks.generate_module_digest_plts(0, 100, 0)
       end},
    "all modules updated" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         Benchmarks.generate_module_digest_plts(0, 0, 100)
       end},
    "1/3 added, 1/3 removed, 1/3 updated" => {
      fn {old_module_digest_plt, new_module_digest_plt} ->
        Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
      end,
      before_scenario: fn _input ->
        Benchmarks.generate_module_digest_plts(33, 33, 34)
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
