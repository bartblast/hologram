defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module45 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module46, warn: false

  route "/test-route-45"

  def template do
    ~H"""
    <Module46 />
    """
  end
end
