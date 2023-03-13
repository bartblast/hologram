defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module53 do
  use Hologram.Page

  layout Hologram.Test.Fixtures.PlaceholderModule1

  route "/test-route-53"

  def template do
    ~H"""
    """
  end
end
