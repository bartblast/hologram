defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module26 do
  use Hologram.Component

  def template do
    ~H"""
    abc{Hologram.Test.Fixtures.Compiler.Pruner.Module20.some_fun_2()}bcd
    """
  end
end
