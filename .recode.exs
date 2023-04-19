alias Recode.Task

[
  autocorrect: true,
  dry: false,
  formatter: {Recode.Formatter, []},
  # TODO: add E2E test app dirs
  inputs: ["*.exs", "{config,lib,test}/**/*.{ex,exs}"],
  tasks: [
    {Task.AliasExpansion, []},
    {Task.AliasOrder, []},
    {Task.EnforceLineLength, active: false},
    {Task.PipeFunOne, []},
    {Task.SinglePipe, []},
    # TODO: add E2E test app dirs
    {Task.Specs, exclude: ["*.exs", "test/**/*.{ex,exs}"], config: [only: :visible]},
    {Task.TestFileExt, []},
    {Task.UnusedVariable, active: false}
  ],
  verbose: false,
  version: "0.4.4"
]
