# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module75 do
  # Query builders computing a bound with a helper of another module, directly and inside a closure.

  import Hologram.Query

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module74

  def capped(messages), do: take(messages, ^Module74.recent_limit())

  def capped_in_closure(messages) do
    limits = Enum.map([:recent], fn _kind -> Module74.recent_limit() end)

    take(messages, ^hd(limits))
  end
end
