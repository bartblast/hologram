# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module38 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module21

  route "/hologram-test-fixtures-compiler-callgraph-module38"

  layout Hologram.Test.Fixtures.DefaultLayout

  def template do
    ~HOLO""
  end

  def action(:action_38, _params, component) do
    put_state(component, :ecto_schema, Module21)
  end
end
