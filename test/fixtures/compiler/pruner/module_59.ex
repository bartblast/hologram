defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module59 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module60

  route "/test-route-59"

  def template do
    ~H"""
    """
  end

  def action do
    Module60
  end
end
