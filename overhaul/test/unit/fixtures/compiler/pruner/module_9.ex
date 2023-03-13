defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module9 do
  use Hologram.Layout
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module10

  def template do
    ~H"""
    """
  end

  def action(:test_9a, _params, _state) do
    Module10.test_fun_10a()
  end
end
