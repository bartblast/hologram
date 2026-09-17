alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Compiler.IR

# Every scenario patches one IR PLT built once. Patching is idempotent for edited modules, so the
# table is only put back where an iteration changed it: a removed module's entry is restored and an
# added module's entry is deleted before each iteration, so every iteration does the same work.
edited_module = Hologram.Compiler
added_module = Hologram.Reflection
removed_module = Hologram.Component

before_scenario = fn diff ->
  ir_plt = Compiler.build_ir_plt()
  removed_irs = Enum.map(diff.removed_modules, &{&1, IR.for_module(&1)})

  {ir_plt, diff, removed_irs}
end

before_each = fn {ir_plt, diff, removed_irs} = input ->
  PLT.put(ir_plt, removed_irs)
  Enum.each(diff.added_modules, &PLT.delete(ir_plt, &1))

  input
end

after_scenario = fn {ir_plt, _diff, _removed_irs} ->
  PLT.stop(ir_plt)
end

Benchee.run(
  %{
    "1 module edited" =>
      {fn {ir_plt, diff, _removed_irs} ->
         Compiler.patch_ir_plt!(ir_plt, diff)
       end,
       before_scenario: fn _input ->
         before_scenario.(%{
           added_modules: [],
           removed_modules: [],
           edited_modules: [edited_module]
         })
       end,
       before_each: before_each,
       after_scenario: after_scenario},
    "1 module added, 1 removed, 1 edited" =>
      {fn {ir_plt, diff, _removed_irs} ->
         Compiler.patch_ir_plt!(ir_plt, diff)
       end,
       before_scenario: fn _input ->
         before_scenario.(%{
           added_modules: [added_module],
           removed_modules: [removed_module],
           edited_modules: [edited_module]
         })
       end,
       before_each: before_each,
       after_scenario: after_scenario}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.patch_ir_plt!/2", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
