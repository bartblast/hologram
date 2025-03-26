defmodule Hologram.Test.Fixtures.Compiler.Module11 do
  use Hologram.Page

  route "/hologram-test-fixtures-compiler-module11"

  layout Hologram.Test.Fixtures.Compiler.Module6

  @impl Page
  def template do
    ~HOLO"""
    Module11 template
    """
  end
end
