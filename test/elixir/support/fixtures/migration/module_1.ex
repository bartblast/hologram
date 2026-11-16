# A module whose zero-arity function a field access would call, when given the module.
defmodule Hologram.Test.Fixtures.Migration.Module1 do
  @spec name() :: String.t()
  def name, do: "called"
end
