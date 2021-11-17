defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module6 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module7

  route "/test-route-6"

  def template do
    ~H"""
    """
  end

  def action(:test_6a, _params, _state) do
    Module7.test_fun_7a()
  end
end
