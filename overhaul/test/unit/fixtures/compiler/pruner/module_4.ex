defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module4 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module5, warn: false

  route "/test-route-4"

  def template do
    ~H"""
      <Module5 />
    """
  end
end
