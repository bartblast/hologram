# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module145 do
  # Query builders handing anonymous functions to calls the build runs for real.

  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Hologram.Query

  alias Hologram.Entity.Derived
  alias Hologram.Test.Fixtures.Entity.Module36

  def closure_making_field(messages) do
    count =
      [1, 2]
      |> Enum.uniq_by(fn x ->
        if x == 1,
          do: Derived.field(Module36, [:last_read_at]),
          else: Derived.field(Module36, [:channel_id])
      end)
      |> length()

    take(messages, ^count)
  end

  def closure_reading_fields(messages, first, second) do
    count =
      [1, 2]
      |> Enum.uniq_by(fn x -> if x == 1, do: first, else: second end)
      |> length()

    take(messages, ^count)
  end

  def closures_compared(messages, first, second) do
    count =
      [holding(first), holding(second)]
      |> Enum.uniq()
      |> length()

    take(messages, ^count)
  end

  def closures_from_one_fn(messages) do
    count =
      [1, 2]
      |> Enum.map(fn x -> elem({x, fn y -> y end}, 1) end)
      |> Enum.uniq()
      |> length()

    take(messages, ^count)
  end

  def field_on_path_not_taken(messages, field) do
    limits = Enum.map([1], fn x -> if x == 2, do: field, else: x end)

    take(messages, ^hd(limits))
  end

  def improper_list(messages) do
    _improper = wrap_term([1] ++ wrap_term(2))

    take(messages, 1)
  end

  defp holding(value), do: fn _x -> value end
end
