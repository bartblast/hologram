defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module33 do
  use Hologram.Layout
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module34, warn: false

  def template do
    ~H"""
    <Module34 />
    """
  end
end
