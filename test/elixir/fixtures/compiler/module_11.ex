defmodule Hologram.Test.Fixtures.Compiler.Module11 do
  use Hologram.Page

  route "/module_11"

  layout Hologram.Test.Fixtures.Compiler.Module6

  @impl Page
  def template do
    ~H"""
    Module11 template
    """
  end
end
