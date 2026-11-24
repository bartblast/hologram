# credo:disable-for-this-file Credo.Check.Readability.Specs
# The field reflection of an entity whose only time field is a derived one. It's no entity of the
# data model, which refuses a derived field reading a server-only attribute.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Entity14 do
  def __attributes__, do: [{:opens_at, :time, [server_only: true]}]

  def __derived__, do: [{:opening, :time, []}]

  def __system_attributes__, do: []
end
