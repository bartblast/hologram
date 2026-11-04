# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module55 do
  # Query builders another query builder calls.

  def as_given(value), do: value

  def messages_of(channel), do: channel.messages
end
