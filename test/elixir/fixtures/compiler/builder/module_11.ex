defmodule Hologram.Test.Fixtures.Compiler.Builder.Module11 do
  use Hologram.Page

  route "/module_11"

  layout Hologram.Test.Fixtures.Compiler.Builder.Module6

  def template do
    ~H"""
    Module11 template
    """
  end
end
