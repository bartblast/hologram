defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module15 do
  use Hologram.Page

  def action(:test_15) do
    Hologram.Test.Fixtures.Compiler.Pruner.Module16.test_16a()
  end

  def template do
    ~H"""
    """
  end
end
