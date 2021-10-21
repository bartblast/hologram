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

  def action(:test_action, _params, state) do
    state
  end
end
