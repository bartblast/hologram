defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module27 do
  use Hologram.Layout

  def init do
    %{
      a: 1
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
