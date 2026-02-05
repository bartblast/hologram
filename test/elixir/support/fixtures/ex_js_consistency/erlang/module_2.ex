# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.ExJsConsistency.Erlang.Module2 do
  def public_fun_0, do: :ok

  def public_fun(x), do: x + private_fun(x)

  defp private_fun(x), do: x * 2
end
