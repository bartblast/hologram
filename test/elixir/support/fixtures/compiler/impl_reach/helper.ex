# credo:disable-for-this-file Credo.Check.Readability.Specs
# A function only an implementation calls.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Helper do
  def value, do: :ok
end
