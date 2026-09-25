# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Readability.PreferImplicitTry
# credo:disable-for-this-file Credo.Check.Readability.WithSingleClause
# credo:disable-for-this-file Credo.Check.Refactor.CondStatements
# credo:disable-for-this-file Credo.Check.Refactor.VariableRebinding
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module2 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2

  def bound do
    struct = %Struct1{}
    struct
  end

  def case_clauses(value) do
    case value do
      :a -> %Struct1{}
      _other -> %Struct2{}
    end
  end

  def case_named(value) do
    case value do
      %Struct1{} -> value
      _other -> nil
    end
  end

  def case_same_name(value) do
    case value do
      {:a, item} -> {item}
      {:b, item} -> [item]
    end
  end

  def comprehension, do: for(struct <- [%Struct1{}], do: struct)

  def comprehension_into_map,
    do: for({key, value} <- [a: %Struct1{}], into: %{}, do: {key, value})

  def comprehension_reduce do
    for item <- [1], reduce: %Struct1{} do
      acc -> {item, acc}
    end
  end

  def cond_clauses(value) do
    cond do
      value -> %Struct1{}
      true -> %Struct2{}
    end
  end

  def from_list do
    [struct] = [%Struct1{}]
    struct
  end

  def from_map do
    %{a: struct} = %{a: %Struct1{}}
    struct
  end

  def from_struct_field do
    %Struct1{field: field} = %Struct1{field: %Struct2{}}
    field
  end

  def from_tuple do
    {:ok, struct} = {:ok, %Struct1{}}
    struct
  end

  def from_tuple_alternatives(value) do
    {:ok, struct} = if value, do: {:ok, %Struct1{}}, else: {:error, %Struct2{}}
    struct
  end

  def param(value), do: value

  def param_named(%Struct1{} = struct), do: struct

  def param_pattern({:ok, struct}), do: struct

  def rebound do
    value = 1
    value = {value, %Struct1{}}
    value
  end

  def try_catch do
    try do
      :ok
    catch
      value -> value
    end
  end

  def try_else do
    try do
      %Struct1{}
    rescue
      ArgumentError -> :rescued
    else
      struct -> {struct}
    end
  end

  def try_rescue do
    try do
      :ok
    rescue
      error in ArgumentError -> error
    end
  end

  def try_rescue_bare do
    try do
      :ok
    rescue
      error -> error
    end
  end

  def with_else(value) do
    with {:ok, item} <- value do
      {item}
    else
      {:error, reason} -> [reason]
    end
  end

  def with_named(value) do
    with %Struct1{} <- value, do: value
  end

  def with_no_else(value) do
    with {:ok, item} <- value, do: {item}
  end
end
