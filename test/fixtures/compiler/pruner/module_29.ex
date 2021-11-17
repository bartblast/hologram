defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module29 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module30, warn: false

  route "/test-route-29"

  def template do
    ~H"""
    <Module30 />
    """
  end
end
