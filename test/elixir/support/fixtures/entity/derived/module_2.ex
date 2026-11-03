# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Derived.Module2 do
  # A query builder derived fields call.

  import Hologram.Query

  def recent(messages) do
    messages
    |> sort(position: :desc)
    |> take(2)
  end
end
