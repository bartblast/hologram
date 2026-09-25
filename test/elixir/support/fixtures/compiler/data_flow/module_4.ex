# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module4 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2

  def calls_direct, do: direct([1])

  def direct([_head | tail]), do: direct(tail)

  def direct([]), do: %Struct1{}

  # Its answer nests one level deeper on every pass, so it never settles.
  def growing(0), do: %Struct1{}

  def growing(count), do: {growing(count - 1)}

  def join([head | tail], acc), do: join(tail, acc <> head)

  def join([], acc), do: acc

  def mutual_a([_head | tail]), do: mutual_b(tail)

  def mutual_a([]), do: :done

  def mutual_b([_head | tail]), do: mutual_a(tail)

  def mutual_b([]), do: %Struct2{}
end
