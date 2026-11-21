# credo:disable-for-this-file Credo.Check.Readability.Specs
# A protocol only an implementation calls. Its consolidated dispatch functions spell every type that
# implements it.
defprotocol Hologram.Test.Fixtures.Compiler.ImplReach.Protocol2 do
  def run(data)
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol2, for: Atom do
  def run(data), do: data
end
