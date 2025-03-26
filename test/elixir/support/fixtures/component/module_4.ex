# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module4 do
  use Hologram.Component

  prop :a, :string
  prop :b, :integer, opt_1: 111, opt_2: 222

  def template do
    ~HOLO""
  end
end
