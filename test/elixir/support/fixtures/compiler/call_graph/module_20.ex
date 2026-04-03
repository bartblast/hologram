# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module20 do
  use Hologram.Component

  def template do
    ~HOLO"Layout 20 template"
  end

  def fun_20_a, do: :a

  def fun_20_b, do: :b
end
