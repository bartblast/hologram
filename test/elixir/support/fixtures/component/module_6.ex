# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module6 do
  use Hologram.Page

  route "/hologram-test-fixtures-component-module6"

  layout Hologram.Test.Fixtures.LayoutFixture

  def template do
    ~HOLO""
  end
end
