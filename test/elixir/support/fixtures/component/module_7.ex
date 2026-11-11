# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module7 do
  use Hologram.Component

  prop :label, :string

  state :count, :integer, default: 0
  state :user, :map

  def template do
    ~HOLO""
  end
end
