# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.ValueFlow.Module1 do
  alias Hologram.Test.Fixtures.Compiler.ValueFlow.Struct1

  def atom, do: :ok

  def bitstring, do: <<1, 2>>

  def block do
    _ignored = :first
    :ok
  end

  def cons, do: [1 | [:a]]

  def integer, do: 1

  def list, do: [1, :a]

  def map, do: %{a: 1}

  def match, do: _struct = %Struct1{}

  def module_atom, do: __MODULE__

  def nested, do: {:ok, [%Struct1{}]}

  def string, do: "abc"

  def struct, do: %Struct1{}

  def struct_map, do: %{__struct__: Struct1, field: :x}

  def struct_with_fields, do: %Struct1{field: :x}

  def tuple, do: {:ok, 1}

  def unknown(value), do: value
end
