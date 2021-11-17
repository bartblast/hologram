defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module55 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module56

  route "/test-route-55"

  def template do
    ~H"""
    """
  end

  def action do
    Module56
  end
end
