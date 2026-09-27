# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module24 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct7

  def built_field(value), do: struct(Struct7, value).name

  def either_ok(flag), do: if(flag, do: {:ok, []}, else: {:ok, [%Struct1{}]})

  def either(flag) do
    map = if flag, do: %{title: "text"}, else: %{item: %Struct1{}}
    map.title
  end

  def literal_field, do: %Struct7{name: "text", note: %Struct1{}}.name

  def map_key, do: %{title: "text", item: %Struct1{}}.title

  def map_literal, do: %{title: "text", item: %Struct1{}}

  def mixed_keys, do: %{"note" => %Struct1{}, title: "text"}.title
end
