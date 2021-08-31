defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module23 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module20

  def template do
    ~H"""
    """
  end

  def action(:test_23, _, _) do
    IO.inspect(Module20.fun_1())
  end
end
