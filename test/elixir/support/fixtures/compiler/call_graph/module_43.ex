# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module43 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module23
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module24
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module25

  route "/hologram-test-fixtures-compiler-callgraph-module43"

  layout Module23

  def init(_params, component, _server) do
    put_state(component,
      ecto_schema: Module24,
      struct: %Module25{}
    )
  end

  def template do
    ~HOLO"Module43 template"
  end
end
