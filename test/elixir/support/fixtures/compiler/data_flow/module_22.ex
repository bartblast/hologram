# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module22 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  def value, do: {%Struct1{}, %Struct1{}, %Struct1{}, %Struct1{}}
end
