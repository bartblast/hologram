defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module11 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module12, warn: false

  route "/test-route-11"

  def template do
    ~H"""
      <Module12 />
    """
  end
end
