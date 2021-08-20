defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module3 do
  use Hologram.Page

  def template do
    ~H"""
      <Hologram.Test.Fixtures.Compiler.Pruner.Module4 />
    """
  end
end
