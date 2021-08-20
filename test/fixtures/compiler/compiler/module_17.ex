defmodule Hologram.Test.Fixtures.Compiler.Module17 do
  use Hologram.Component

  def template do
    ~H"""
    abc{Hologram.Test.Fixtures.Compiler.Module8.test_fun_8()}xyz
    """
  end
end
