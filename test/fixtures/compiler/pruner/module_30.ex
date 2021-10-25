defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module30 do
  use Hologram.Page

  layout Hologram.Test.Fixtures.Compiler.Pruner.Module31

  def init, do: %{}

  def template do
    ~H"""
    """
  end

  def action(:test_action, _, _) do
    Hologram.Test.Fixtures.Compiler.Pruner.Module32.test_fun()
  end
end
