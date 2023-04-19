alias Recode.Task

[
  autocorrect: true,
  dry: false,
  formatter: {Recode.Formatter, []},
  inputs: ["*.exs", "{config,lib,test}/**/*.{ex,exs}"],
  tasks: [
    {Task.AliasExpansion, []},
    {Task.AliasOrder, []},
    {Task.EnforceLineLength, active: false},
    {Task.PipeFunOne, []},
    {Task.SinglePipe, []},
    {Task.Specs, exclude: ["*.exs", "test/**/*.{ex,exs}"], config: [only: :visible]},
    {Task.TestFileExt, []},
    {Task.UnusedVariable, active: false}
  ],
  verbose: false,
  version: "0.4.4"
]
