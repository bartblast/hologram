defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module52 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module53

  route "/test-route-52"


  def template do
    ~H"""
    """
  end

  def action do
    Module53
  end
end
