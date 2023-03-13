defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module5 do
  use Hologram.Component

  def template do
    ~H"""
    """
  end

  def action(:test_5a, _params, _state) do
    :ok
  end

  def action(:test_5b, _a, _b, _c) do
    :ok
  end
end
