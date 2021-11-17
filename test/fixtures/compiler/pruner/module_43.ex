defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module43 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module44, warn: false

  route "/test-route-43"

  def template do
    ~H"""
    <Module44 />
    """
  end
end
