defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module2 do
  use Hologram.Page

  layout Hologram.Test.Fixtures.Compiler.Pruner.Module3

  route "/test-route-2"

  def template do
    ~H"""
    """
  end

  def action(:test_2a, _params, _state) do
    :ok
  end

  def action(:test_2b, _a, _b, _c) do
    :ok
  end
end
