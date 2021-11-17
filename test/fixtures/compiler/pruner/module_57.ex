defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module57 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module58

  route "/test-route-57"

  def template do
    ~H"""
    """
  end

  def action do
    Module58.test_fun_58b()
  end
end
