# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1 do
  def my_public_fun(x), do: x

  def my_public_fun(x, 2), do: x + 2

  def fix_unused_private_fun_warning, do: my_private_fun(1, 2)

  defp my_private_fun(x, y), do: x - y
end
