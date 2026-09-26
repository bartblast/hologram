# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module19 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  def bare, do: :done

  def erlang_module, do: :lists

  def field(value), do: value.title

  def module, do: Struct1

  def nested(value), do: elem(elem(value, 0), 0)

  def single(value), do: elem(value, 0)

  def tagged, do: {:ok, :done}
end
