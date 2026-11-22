# credo:disable-for-this-file Credo.Check.Readability.Specs
# A struct whose implementation is the only code on its page that checks permissions.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Struct2 do
  defstruct []
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol,
  for: Hologram.Test.Fixtures.Compiler.ImplReach.Struct2 do
  alias Hologram.Auth
  alias Hologram.Test.Fixtures.Entity.Module2

  def run(_struct), do: Auth.can?(nil, :read, %Module2{})
end
