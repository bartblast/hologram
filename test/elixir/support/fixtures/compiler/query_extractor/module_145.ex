# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module145 do
  # Query builders handing anonymous functions to calls the build runs for real.

  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Hologram.Query

  alias Hologram.Entity.Derived
  alias Hologram.Test.Fixtures.Entity.Module36

  def by_computed_key(messages, key) do
    limit = if key == "ab", do: 1, else: 2

    take(messages, ^limit)
  end

  def by_computed_flag(messages, flag) do
    limit = if flag, do: 1, else: 2

    take(messages, ^limit)
  end

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

  def guard_on_argument(messages) do
    limit =
      [1]
      |> Enum.map(fn x when x > 10 -> 5 end)
      |> hd()

    take(messages, ^limit)
  end

  def guard_held(messages) do
    limit =
      [20]
      |> Enum.map(fn x when x > 10 -> 5 end)
      |> hd()

    take(messages, ^limit)
  end

  def guard_on_outer_value(messages) do
    bound = wrap_term(10)

    limit =
      [1]
      |> Enum.map(fn x when x > bound -> 5 end)
      |> hd()

    take(messages, ^limit)
  end

  def guard_on_outer_value_held(messages) do
    bound = wrap_term(10)

    limit =
      [20]
      |> Enum.map(fn x when x > bound -> 5 end)
      |> hd()

    take(messages, ^limit)
  end

  def improper_list(messages) do
    _improper = wrap_term([1] ++ wrap_term(2))

    take(messages, 1)
  end

  def keyed_by_one(messages) do
    opts = %{nil => 1, one(messages) => 3}

    take(messages, ^opts.nil)
  end

  def literal_param(messages) do
    limit =
      [2]
      |> wrap_term()
      |> Enum.map(fn 1 -> 5 end)
      |> hd()

    take(messages, ^limit)
  end

  def literal_param_matched(messages) do
    limit =
      [1]
      |> wrap_term()
      |> Enum.map(fn 1 -> 5 end)
      |> hd()

    take(messages, ^limit)
  end

  def keyed_by_computed(messages, key) do
    opts = %{:limit => 3, key => 1}

    take(messages, ^opts.limit)
  end

  def map_equal_keys_literal_last(messages) do
    key = wrap_term(:limit)
    opts = %{key => 1, limit: 3}

    take(messages, ^opts.limit)
  end

  def map_equal_keys_variable_last(messages) do
    key = wrap_term(:limit)
    opts = %{:limit => 1, key => 3}

    take(messages, ^opts.limit)
  end

  def repeated_param(messages) do
    limit =
      [1]
      |> wrap_term()
      |> Enum.reduce(2, fn x, x -> 5 end)

    take(messages, ^limit)
  end

  def repeated_param_equal(messages) do
    limit =
      [2]
      |> wrap_term()
      |> Enum.reduce(2, fn x, x -> 5 end)

    take(messages, ^limit)
  end

  def refusal_rescued(messages) do
    count =
      [1, 2]
      |> __MODULE__.rescuing(fn x ->
        {y} = {x}
        y
      end)
      |> length()

    take(messages, ^count)
  end

  def refusal_replaced(messages) do
    count =
      [1, 2]
      |> __MODULE__.raising_its_own(fn x ->
        {y} = {x}
        y
      end)
      |> length()

    take(messages, ^count)
  end

  def refusal_thrown_over(messages) do
    count =
      [1, 2]
      |> __MODULE__.throwing_its_own(fn x ->
        {y} = {x}
        y
      end)
      |> length()

    take(messages, ^count)
  end

  def erlang_error_caught(messages) do
    limit = __MODULE__.catching_badarg(["x"], fn x -> String.to_integer(x) end)

    take(messages, ^limit)
  end

  def formatted_error_caught(messages) do
    limit = __MODULE__.catching_reason([1], fn x -> __MODULE__.failing(x) end)

    take(messages, ^limit)
  end

  def catching_reason(list, fun) do
    _results = Enum.map(list, fun)

    3
  catch
    :error, :my_reason -> 2
    :error, _other -> 6
  end

  def failing(value),
    do: :erlang.error(:my_reason, [value], error_info: %{function: :format_error})

  def format_error(_reason, _stacktrace), do: "not a map"

  def catching_badarg(list, fun) do
    _results = Enum.map(list, fun)

    3
  catch
    :error, :badarg -> 1
    :error, _other -> 2
  end

  def throwing_its_own(list, fun) do
    Enum.map(list, fun)
  rescue
    _error -> throw(:helper_throw)
  end

  def raising_its_own(list, fun) do
    Enum.map(list, fun)
  rescue
    _error -> reraise ArgumentError, "the helper's own error", []
  end

  def refusal_in_task(messages) do
    count =
      [1, 2]
      |> __MODULE__.rescuing_in_task(fn x ->
        {y} = {x}
        y
      end)
      |> Enum.uniq()
      |> length()

    take(messages, ^count)
  end

  def harmless_in_task(messages) do
    count =
      [1, 2]
      |> __MODULE__.running_in_task(fn x -> x + 1 end)
      |> Enum.uniq()
      |> length()

    take(messages, ^count)
  end

  def running_in_task(list, fun) do
    list
    |> Enum.map(fn x -> Task.async(fn -> fun.(x) end) end)
    |> Task.await_many()
  end

  def rescuing_in_task(list, fun) do
    list
    |> Enum.map(fn x -> Task.async(fn -> rescuing_call(fun, x) end) end)
    |> Task.await_many()
  end

  def rescuing(list, fun) do
    Enum.map(list, fun)
  rescue
    _error -> []
  end

  defp holding(value), do: fn _x -> value end

  defp rescuing_call(fun, value) do
    fun.(value)
  rescue
    _error -> :fallback
  end
end
