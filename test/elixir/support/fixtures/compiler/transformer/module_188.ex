# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Transformer.Module188 do
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module188

  defstruct [:a, :b]

  def test(x) do
    # credo:disable-for-lines:5 Credo.Check.Readability.PreferImplicitTry
    try do
      x
    catch
      :throw, %Module188{a: a} -> a
    end
  end
end
