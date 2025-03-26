# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Reflection.Module6 do
  use Hologram.Page

  route "/hologram-test-fixtures-commons-reflection-module6"

  layout Hologram.Test.Fixtures.LayoutFixture

  def template do
    ~HOLO"""
    Module6 template
    """
  end
end
