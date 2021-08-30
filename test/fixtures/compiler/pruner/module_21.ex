defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module21 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module20

  def template do
    ~H"""
    """
  end

  def action(:test_21, _, _) do
    Module20.route()
  end
end
