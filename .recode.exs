[
  version: "0.7.2",
  autocorrect: true,
  color: true,
  dry: false,
  formatters: [Recode.CLIFormatter],
  inputs: [
    "{.formatter,mix}.exs",
    "{benchmarks,config,lib}/**/*.{ex,exs}",
    "test/elixir/**/*.{ex,exs}",
    "test/features/{.formatter,mix}.exs",
    "test/features/{app,config,lib,test}/**/*.{ex,exs}"
  ],
  verbose: false,
  tasks: [
    {Recode.Task.AliasExpansion, []},
    {Recode.Task.AliasOrder, []},
    {Recode.Task.Dbg, [autocorrect: false]},
    {Recode.Task.EnforceLineLength, [active: false]},
    {Recode.Task.FilterCount, []},
    {Recode.Task.IOInspect, [active: false, autocorrect: false]},
    {Recode.Task.Nesting, [active: false]},
    {Recode.Task.PipeFunOne, []},
    {Recode.Task.SinglePipe, []},
    {Recode.Task.Specs,
     [active: false, config: [only: :visible], exclude: ["test/**/*.{ex,exs}", "mix.exs"]]},
    {Recode.Task.TagFIXME, [active: false, exit_code: 2]},
    {Recode.Task.TagTODO, [active: false, exit_code: 4]},
    {Recode.Task.TestFileExt, []},
    {Recode.Task.UnusedVariable, []}
  ]
]
