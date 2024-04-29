# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module5 do
  use Hologram.Page

  route "/hologram-test-fixtures-compiler-module5"

  layout Hologram.Test.Fixtures.LayoutFixture

  def template do
    ~H"""
    Module5 template
    """
  end
end
