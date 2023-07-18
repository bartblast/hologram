# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Runtime.Component.Module2 do
  use Hologram.Component

  def init(_props), do: :overridden_1

  def init(_props, _conn), do: :overridden_2
end
