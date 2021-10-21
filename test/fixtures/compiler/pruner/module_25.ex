defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module25 do
  use Hologram.Component

  def init do
    %{
      a: 1,
      b: 2
    }
  end

  def template do
    ~H"""
    """
  end
end
