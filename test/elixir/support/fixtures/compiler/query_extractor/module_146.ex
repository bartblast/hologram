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
      computed_picked: {"lib/my_app/member.ex", 10}
    }
  end
end
