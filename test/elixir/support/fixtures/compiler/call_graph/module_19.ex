# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module19 do
  use Hologram.Page

  route "/hologram-test-fixtures-compiler-callgraph-module19"

  layout Hologram.Test.Fixtures.Compiler.CallGraph.Module20

  def init(_params, component, _server) do
    component
  end

  def template do
    ~HOLO"Page 19 template"
  end

  def fun_19_a, do: :a

  def fun_19_b, do: :b
end
