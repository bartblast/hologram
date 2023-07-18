defmodule Hologram.Test.Fixtures.Runtime.Layout.Module2 do
  use Hologram.Layout

  def init(_props, _conn), do: :overridden
end
