defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module32 do
  use Hologram.Page

  layout Hologram.Test.Fixtures.Compiler.Pruner.Module31

  def init, do: %{}

  def template do
    ~H"""
    """
  end

  def test_fun, do: nil
end
