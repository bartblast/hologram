defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module22 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module20

  def template do
    ~H"""
    """
  end

  def action(:test_22, _, _) do
    if Module20.fun_1() do
      Module20.fun_2()
    else
      Module20.fun_3()
    end
  end
end
