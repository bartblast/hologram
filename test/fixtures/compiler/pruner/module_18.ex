defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module18 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module19, warn: false

  route "/test-route-18"

  def template do
    ~H"""
    <Module19 />
    """
  end
end
