defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module17 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module16, warn: false

  def action(:test_15) do
    15
  end

  def template do
    ~H"""
    """
  end
end
