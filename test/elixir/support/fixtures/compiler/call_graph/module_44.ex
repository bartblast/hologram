# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module44 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module23
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module24
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module25

  route "/hologram-test-fixtures-compiler-callgraph-module44"

  layout Module23

  def init(_params, component, _server) do
    put_state(component,
      ecto_schema: Module24,
      struct: %Module25{}
    )
  end

  def template do
    ~HOLO"Module44 template"
  end

  def action(:reflect, _params, component) do
    ecto_schema = component.state.ecto_schema
    put_state(component, :fields, ecto_schema.__changeset__())
  end
end
