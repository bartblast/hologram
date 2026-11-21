# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module143 do
  # A query builder the cover test cover-compiles - no other test reads it, since a cover-compiled
  # module is what every test running beside it would read.

  import Hologram.Query

  def recent(messages, limit) when limit > 2, do: take(messages, 2)

  def recent(messages, limit), do: take(messages, ^limit)
end
