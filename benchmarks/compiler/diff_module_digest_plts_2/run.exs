alias Hologram.Benchmarks
alias Hologram.Compiler

Benchee.run(
  %{
    "no module changes" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         Benchmarks.generate_module_digest_plts(0, 0, 0)
       end},
    "1 module added" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         Benchmarks.generate_module_digest_plts(1, 0, 0)
       end},
    "1 module removed" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         Benchmarks.generate_module_digest_plts(0, 1, 0)
       end},
    "1 module updated" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         Benchmarks.generate_module_digest_plts(0, 0, 1)
       end},
    "100% modules added" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         Benchmarks.generate_module_digest_plts(1.0, 0.0, 0.0)
       end},
    "100% modules removed" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         Benchmarks.generate_module_digest_plts(0.0, 1.0, 0.0)
       end},
    "100% modules updated" =>
      {fn {old_module_digest_plt, new_module_digest_plt} ->
         Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
       end,
       before_scenario: fn _input ->
         Benchmarks.generate_module_digest_plts(0.0, 0.0, 1.0)
       end},
    "33% added, 33% removed, 34% updated" => {
      fn {old_module_digest_plt, new_module_digest_plt} ->
        Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
      end,
      before_scenario: fn _input ->
        Benchmarks.generate_module_digest_plts(0.33, 0.33, 0.34)
      end
    },
    "1% added, 1% removed, 1% updated" => {
      fn {old_module_digest_plt, new_module_digest_plt} ->
        Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
      end,
      before_scenario: fn _input ->
        Benchmarks.generate_module_digest_plts(0.01, 0.01, 0.01)
      end
    },
    "10 added, 10 removed, 10 updated" => {
      fn {old_module_digest_plt, new_module_digest_plt} ->
        Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
      end,
      before_scenario: fn _input ->
        Benchmarks.generate_module_digest_plts(10, 10, 10)
      end
    },
    "3 added, 3 removed, 3 updated" => {
      fn {old_module_digest_plt, new_module_digest_plt} ->
        Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
      end,
      before_scenario: fn _input ->
        Benchmarks.generate_module_digest_plts(3, 3, 3)
      end
    },
    "1 added, 1 removed, 1 updated" => {
      fn {old_module_digest_plt, new_module_digest_plt} ->
        Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)
      end,
      before_scenario: fn _input ->
        Benchmarks.generate_module_digest_plts(1, 1, 1)
      end
    }
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.diff_module_digest_plts/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
