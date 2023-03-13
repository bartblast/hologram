defmodule Hologram.Test.Fixtures.Compiler.Builder.Module1 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.Builder.Module2, warn: false
  alias Hologram.Test.Fixtures.Compiler.Builder.Module3

  route "/test-route-1"

  def action(:test, _a, _b) do
    Module3.test_3()
  end

  def template do
    ~H"""
    """
  end
end
