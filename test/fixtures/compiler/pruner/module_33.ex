defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module33 do
  use Hologram.Page

  route "/test/route/33"

  def template do
    ~H"""
    """
  end

  def action(:test_action, _, _) do
    Hologram.Test.Fixtures.Compiler.Pruner.Module34
  end
end
