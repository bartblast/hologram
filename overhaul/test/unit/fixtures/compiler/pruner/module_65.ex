defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module65 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module66

  route "/test-route-65"

  def template do
    ~H"""
    """
  end

  def action do
    Module66
  end
end
