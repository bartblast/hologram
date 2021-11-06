defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module12 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module13

  def template do
    ~H"""
    """
  end

  def action(:test_12a, _params, _state) do
    Module13.test_fun_13a()
  end
end
