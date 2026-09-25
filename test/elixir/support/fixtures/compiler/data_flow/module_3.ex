# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module3 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module2
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2

  def build, do: %Struct1{}

  def build_from(value), do: %Struct1{field: value}

  def calls_build, do: build()

  def calls_build_from, do: build_from(%Struct2{})

  def calls_erlang(list), do: :lists.reverse(list)

  def calls_ignores, do: ignores(build())

  def calls_remote, do: Module2.bound()

  def calls_wrap do
    {:ok, struct} = wrap(%Struct1{})
    struct
  end

  def drops_result do
    build()
    :ok
  end

  def identity(value), do: value

  def ignores(_value), do: :ok

  def recursive(0), do: %Struct1{}

  def recursive(count), do: recursive(count - 1)

  def two_clauses(:a), do: %Struct1{}

  def two_clauses(_value), do: %Struct2{}

  def wrap(value), do: {:ok, value}
end
