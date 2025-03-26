# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module14 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module16

  route "/hologram-test-fixtures-compiler-callgraph-module14"

  layout Hologram.Test.Fixtures.Compiler.CallGraph.Module15

  def template do
    ~HOLO"""
    Module14 template
    """
  end

  def action(:action_14a, params, component) do
    Module16.my_fun_16a(params, component)
  end

  def action(:action_14b, _params, component) do
    component
    |> Enum.to_list()
    |> :erlang.hd()
  end

  def action(:action_14c, _params, _component) do
    Kernel.inspect(123)
  end
end
