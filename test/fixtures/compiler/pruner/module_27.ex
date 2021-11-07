defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module27 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module28, warn: false

  def template do
    ~H"""
    {Module28.test_28a()}
    """
  end
end
