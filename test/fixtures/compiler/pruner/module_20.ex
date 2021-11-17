defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module20 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module21, warn: false

  route "/test-route-20"

  def template do
    ~H"""
      {Module21.test_21a()}
    """
  end
end
