defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module3 do
  use Hologram.Layout

  def template do
    ~H"""
    """
  end

  def action(:test_3a, _params, _state) do
    :ok
  end

  def action(:test_3b, _a, _b, _c) do
    :ok
  end
end
