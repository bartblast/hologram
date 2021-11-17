defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module35 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module36, warn: false

  route "/test-route-35"

  def template do
    ~H"""
    <Module36 />
    """
  end
end
