# credo:disable-for-this-file Credo.Check.Readability.Specs
# A protocol only implementations call, with a function no code calls.
defprotocol Hologram.Test.Fixtures.Compiler.ImplReach.Protocol3 do
  def export(data)

  def purge(data)
end
