# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Runtime.Page.Module2 do
  use Hologram.Page

  def init(_params, _conn), do: %{overridden: true}
end
