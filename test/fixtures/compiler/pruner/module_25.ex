defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module25 do
  use Hologram.Page

  def template do
    ~H"""
    abc{Hologram.Test.Fixtures.Compiler.Pruner.Module20.some_fun_2()}bcd
    """
  end
end
