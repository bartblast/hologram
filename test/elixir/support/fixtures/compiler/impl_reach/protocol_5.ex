# credo:disable-for-this-file Credo.Check.Readability.Specs
# A protocol with an app's implementation for a struct type a row's field boxes to.
defprotocol Hologram.Test.Fixtures.Compiler.ImplReach.Protocol5 do
  def run(data)
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol5, for: Date do
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity15

  def run(_date), do: filter(Entity15, label == "dated")
end
