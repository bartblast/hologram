# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module63 do
  # A query builder whose clause a guard on its argument decides.

  import Hologram.Query

  def guarded(messages, limit) when limit > 3, do: take(messages, 3)

  def guarded(messages, _limit), do: messages
end
