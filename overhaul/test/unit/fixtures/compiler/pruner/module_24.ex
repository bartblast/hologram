defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module24 do
  use Hologram.Layout
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module25, warn: false

  def template do
    ~H"""
    {Module25.test_25a()}
    """
  end
end
