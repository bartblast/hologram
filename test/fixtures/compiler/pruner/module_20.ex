defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module20 do
  use Hologram.Page

  route "/test-route"

  def template do
    ~H"""
    """
  end
end
