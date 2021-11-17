defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module49 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module50

  route "/test-route-49"

  def template do
    ~H"""
    """
  end

  def action do
    Module50
  end
end
