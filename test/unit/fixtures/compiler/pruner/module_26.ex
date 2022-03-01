defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module26 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module27, warn: false

  route "/test-route-26"

  def template do
    ~H"""
    <Module27 />
    """
  end
end
