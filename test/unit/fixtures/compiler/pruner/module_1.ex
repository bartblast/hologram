defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module1 do
  use Hologram.Page

  route "/test-route-1"

  def template do
    ~H"""
    """
  end

  def action(:test_1a, _params, _state) do
    :ok
  end

  def action(:test_1b, _a, _b, _c) do
    :ok
  end
end
