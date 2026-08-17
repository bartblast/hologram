# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module184 do
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module184

  defstruct [:a, :b]

  def test(x) do
    # credo:disable-for-lines:7 Credo.Check.Readability.PreferImplicitTry
    try do
      x
    catch
      :error -> :a
    else
      %Module184{a: a} -> a
    end
  end
end
