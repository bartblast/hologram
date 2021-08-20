defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module18 do
  use Hologram.Page

  def action(:test_18) do
    Hologram.Test.Fixtures.Compiler.Pruner.Module19.test_19()
  end

  def template do
    ~H"""
    """
  end

  def test_18 do
    18
  end
end
