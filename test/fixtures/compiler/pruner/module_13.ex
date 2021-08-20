defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module13 do
  use Hologram.Page

  def template do
    ~H"""
    abc{Hologram.Test.Fixtures.Compiler.Pruner.Module8.test_8()}xyz
    """
  end
end
