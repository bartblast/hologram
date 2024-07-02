# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module17 do
  use Hologram.Page

  route "/hologram-test-fixtures-compiler-callgraph-module17"

  layout Hologram.Test.Fixtures.DefaultLayout

  def template do
    ~H""
  end

  def action(:action_17, _params, component) do
    Inspect.Integer.__impl__(:for)
    Inspect.Integer.inspect(123, %Inspect.Opts{})

    apply(Inspect.Hex.Solver.PackageRange, :__impl__, [:for])
    apply(Inspect.Hex.Solver.PackageRange, :inspect, [:dummy, %Inspect.Opts{}])

    String.Chars.Integer.__impl__(:for)
    String.Chars.Integer.to_string(123)

    apply(String.Chars.Hex.Solver.PackageRange, :__impl__, [:for])
    apply(String.Chars.Hex.Solver.PackageRange, :inspect, [:dummy, %Inspect.Opts{}])

    apply(Hologram.Test.Fixtures.Compiler.CallGraph.Module18, :my_fun_18, [1, 2])

    component
  end
end
