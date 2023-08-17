defmodule Hologram.Test.Fixtures.Compiler.Reflection.Module2 do
  use Hologram.Page

  route "/module_2"

  layout Hologram.Test.Fixtures.Compiler.Reflection.Module4

  @impl Page
  def template do
    ~H"""
    Module2 template
    """
  end
end
