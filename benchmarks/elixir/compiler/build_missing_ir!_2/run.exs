alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Reflection

# "Nothing missing" is a warm compile asking for IR the kept PLT already holds: one membership
# check per module. "All missing" is a first compile in a VM filling an empty PLT, which gets a
# fresh empty PLT before each iteration and has it stopped after.
Benchee.run(
  %{
    "nothing missing" =>
      {fn {ir_plt, modules} ->
         Compiler.build_missing_ir!(ir_plt, modules)
       end,
       before_scenario: fn _input ->
         ir_plt = Compiler.build_ir_plt()

         {ir_plt, PLT.keys(ir_plt)}
       end,
       after_scenario: fn {ir_plt, _modules} ->
         PLT.stop(ir_plt)
       end},
    "all missing" =>
      {fn {ir_plt, modules} ->
         Compiler.build_missing_ir!(ir_plt, modules)
       end,
       before_scenario: fn _input ->
         Reflection.list_elixir_modules()
       end,
       before_each: fn modules ->
         {PLT.start(), modules}
       end,
       after_each: fn ir_plt ->
         PLT.stop(ir_plt)
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_missing_ir!/2", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
