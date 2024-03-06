# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module13 do
  def fun_b(_a, _b), do: nil

  def fun_d(a, b, _c, _d), do: fun_e(a, b)

  defp fun_e(_a, _b), do: nil
end
