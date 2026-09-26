# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module23 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2

  def value, do: {%Struct2{}, %Struct2{}, %Struct2{}, %Struct2{}}
end
