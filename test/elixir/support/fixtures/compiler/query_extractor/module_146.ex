# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module146 do
  # Stands for an entity type whose derived fields call the query builders of Module145. The
  # definitions read the fields of an entity type that compiles.

  alias Hologram.Entity.Derived
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module145
  alias Hologram.Test.Fixtures.Entity.Module36

  # Some definitions are refused on purpose, so their calls fail.
  @dialyzer {:nowarn_function, __derived_definition__: 1}

  def __derived_definition__(:computed_condition) do
    condition = Derived.condition(Module36, last_read_at: nil)

    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.by_computed_flag(condition)
    |> Derived.lower()
  end

  def __derived_definition__(:computed_joined) do
    joined =
      Derived.concat([
        Derived.field(Module36, [:last_read_at]),
        Derived.field(Module36, [:channel_id])
      ])

    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.by_computed_key(joined)
    |> Derived.lower()
  end

  def __derived_definition__(:computed_key) do
    condition = Derived.condition(Module36, last_read_at: nil)
    key = Derived.if_value(condition, :limit, :other)

    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.keyed_by_computed(key)
    |> Derived.lower()
  end

  def __derived_definition__(:computed_picked) do
    condition = Derived.condition(Module36, last_read_at: nil)
    picked = Derived.if_value(condition, "ab", "cd")

    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.by_computed_key(picked)
    |> Derived.lower()
  end

  def __derived_definition__(:closure_making_field) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.closure_making_field()
    |> Derived.lower()
  end

  def __derived_definition__(:closure_reading_fields) do
    first = Derived.field(Module36, [:last_read_at])
    second = Derived.field(Module36, [:channel_id])

    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.closure_reading_fields(first, second)
    |> Derived.lower()
  end

  def __derived_definition__(:closures_compared) do
    first = Derived.field(Module36, [:last_read_at])
    second = Derived.field(Module36, [:channel_id])

    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.closures_compared(first, second)
    |> Derived.lower()
  end

  def __derived_definition__(:closures_from_one_fn) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.closures_from_one_fn()
    |> Derived.lower()
  end

  def __derived_definition__(:field_on_path_not_taken) do
    field = Derived.field(Module36, [:last_read_at])

    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.field_on_path_not_taken(field)
    |> Derived.lower()
  end

  def __derived_definition__(:improper_list) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.improper_list()
    |> Derived.lower()
  end

  def __derived_definition__(:guard_on_argument) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.guard_on_argument()
    |> Derived.lower()
  end

  def __derived_definition__(:guard_on_outer_value) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.guard_on_outer_value()
    |> Derived.lower()
  end

  def __derived_definition__(:literal_param) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.literal_param()
    |> Derived.lower()
  end

  def __derived_definition__(:repeated_param) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.repeated_param()
    |> Derived.lower()
  end

  def __derived_definition__(:guard_held) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.guard_held()
    |> Derived.lower()
  end

  def __derived_definition__(:guard_on_outer_value_held) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.guard_on_outer_value_held()
    |> Derived.lower()
  end

  def __derived_definition__(:literal_param_matched) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.literal_param_matched()
    |> Derived.lower()
  end

  def __derived_definition__(:repeated_param_equal) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.repeated_param_equal()
    |> Derived.lower()
  end

  def __derived_definition__(:map_equal_keys_literal_last) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.map_equal_keys_literal_last()
    |> Derived.lower()
  end

  def __derived_definition__(:map_equal_keys_variable_last) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.map_equal_keys_variable_last()
    |> Derived.lower()
  end

  def __derived_definition__(:keyed_by_one) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.keyed_by_one()
    |> Derived.lower()
  end

  def __derived_definition__(:refusal_rescued) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.refusal_rescued()
    |> Derived.lower()
  end

  def __derived_definition__(:refusal_replaced) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.refusal_replaced()
    |> Derived.lower()
  end

  def __derived_definition__(:refusal_thrown_over) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.refusal_thrown_over()
    |> Derived.lower()
  end

  def __derived_definition__(:erlang_error_caught) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.erlang_error_caught()
    |> Derived.lower()
  end

  def __derived_definition__(:formatted_error_caught) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module145.formatted_error_caught()
    |> Derived.lower()
  end

  def __derived_locations__ do
    %{
      closure_making_field: {"lib/my_app/member.ex", 1},
      closure_reading_fields: {"lib/my_app/member.ex", 2},
      closures_compared: {"lib/my_app/member.ex", 3},
      closures_from_one_fn: {"lib/my_app/member.ex", 4},
      field_on_path_not_taken: {"lib/my_app/member.ex", 5},
      improper_list: {"lib/my_app/member.ex", 6},
      computed_condition: {"lib/my_app/member.ex", 7},
      computed_joined: {"lib/my_app/member.ex", 8},
      computed_key: {"lib/my_app/member.ex", 9},
      computed_picked: {"lib/my_app/member.ex", 10},
      guard_on_argument: {"lib/my_app/member.ex", 11},
      guard_on_outer_value: {"lib/my_app/member.ex", 12},
      literal_param: {"lib/my_app/member.ex", 13},
      repeated_param: {"lib/my_app/member.ex", 14},
      guard_held: {"lib/my_app/member.ex", 15},
      guard_on_outer_value_held: {"lib/my_app/member.ex", 16},
      literal_param_matched: {"lib/my_app/member.ex", 17},
      repeated_param_equal: {"lib/my_app/member.ex", 18},
      map_equal_keys_literal_last: {"lib/my_app/member.ex", 19},
      map_equal_keys_variable_last: {"lib/my_app/member.ex", 20},
      keyed_by_one: {"lib/my_app/member.ex", 21},
      refusal_rescued: {"lib/my_app/member.ex", 22},
      refusal_replaced: {"lib/my_app/member.ex", 23},
      refusal_thrown_over: {"lib/my_app/member.ex", 24},
      erlang_error_caught: {"lib/my_app/member.ex", 25},
      formatted_error_caught: {"lib/my_app/member.ex", 26}
    }
  end
end
