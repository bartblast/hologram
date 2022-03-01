defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module41 do
  use Hologram.Layout
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module42

  def init do
    Module42.test_fun_42a()
  end

  def template do
    ~H"""
    """
  end
end
