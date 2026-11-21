# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142 do
  # Stands for an entity type whose derived fields call query builders with values the build knows,
  # which decide the builders' branches and clauses or are refused, at locations the refusals name.
  # The definitions read the fields of entity types that compile.

  import Hologram.Query, only: [take: 2]

  alias Hologram.Entity.Derived
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module141
  alias Hologram.Test.Fixtures.Entity.Module36

  # Some definitions hand builders values no clause takes, which is what the walk refuses - so their
  # calls fail on purpose.
  @dialyzer {:nowarn_function, __derived_definition__: 1}

  def __derived_definition__(:body_match) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.matched()
    |> Derived.lower()
  end

  def __derived_definition__(:bounded_large) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.bounded(20)
    |> Derived.lower()
  end

  def __derived_definition__(:bounded_small) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.bounded(5)
    |> Derived.lower()
  end

  def __derived_definition__(:by_case) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.by_case(:recent)
    |> Derived.lower()
  end

  def __derived_definition__(:case_unmatched) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.by_case(:closed)
    |> Derived.lower()
  end

  def __derived_definition__(:composite) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.tagged(:recent)
    |> Derived.lower()
  end

  def __derived_definition__(:cond_sized) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.sized(3)
    |> Derived.lower()
  end

  def __derived_definition__(:cond_unmatched) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.strictly_sized(0)
    |> Derived.lower()
  end

  def __derived_definition__(:destructured) do
    messages = Derived.field(Module36, [:channel, :messages])

    {messages, 1}
    |> Module141.first_of()
    |> Derived.lower()
  end

  def __derived_definition__(:either) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.either(:two)
    |> Derived.lower()
  end

  def __derived_definition__(:four_ary) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.four_ary()
    |> Derived.lower()
  end

  def __derived_definition__(:if_strict) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.strict_or_all(true)
    |> Derived.lower()
  end

  def __derived_definition__(:invalid) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.invalid()
    |> Derived.lower()
  end

  def __derived_definition__(:kind_unmatched) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.by_kind(:closed)
    |> Derived.lower()
  end

  def __derived_definition__(:listed) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.listed(:none)
    |> Derived.lower()
  end

  def __derived_definition__(:narrowed) do
    Module36
    |> Derived.field([:channel, :messages])
    |> take(2)
    |> Module141.channel_of()
    |> Derived.lower()
  end

  def __derived_definition__(:no_such_field) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.misspelled(%{limit: 2})
    |> Derived.lower()
  end

  def __derived_definition__(:not_a_map) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.limited(5)
    |> Derived.lower()
  end

  def __derived_definition__(:outside) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Function.identity()
    |> Derived.lower()
  end

  def __derived_definition__(:same) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.same(1, 2)
    |> Derived.lower()
  end

  def __derived_definition__(:undefined) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.undefined()
    |> Derived.lower()
  end

  def __derived_definition__(:wildcard_bound) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.wildcard_bound()
    |> Derived.lower()
  end

  def __derived_definition__(:wildcard_invalid) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.wildcard_invalid()
    |> Derived.lower()
  end

  def __derived_definition__(:undefined_native) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.undefined_native()
    |> Derived.lower()
  end

  def __derived_definition__(:undefined_inside_native) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.undefined_inside_native()
    |> Derived.lower()
  end

  def __derived_definition__(:not_a_module_target) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.not_a_module_target()
    |> Derived.lower()
  end

  def __derived_definition__(:keyed_by_field) do
    key = Derived.field(Module36, [:last_read_at])

    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.keyed(%{key => true})
    |> Derived.lower()
  end

  def __derived_definition__(:keyed_read) do
    key = Derived.field(Module36, [:last_read_at])

    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.keyed_read(%{nil => 2, key => 1})
    |> Derived.lower()
  end

  def __derived_definition__(:windowed) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module141.windowed(1, 5)
    |> Derived.lower()
  end

  def __derived_locations__ do
    %{
      body_match: {"lib/my_app/member.ex", 7},
      bounded_large: {"lib/my_app/member.ex", 9},
      bounded_small: {"lib/my_app/member.ex", 11},
      by_case: {"lib/my_app/member.ex", 13},
      case_unmatched: {"lib/my_app/member.ex", 15},
      composite: {"lib/my_app/member.ex", 17},
      cond_sized: {"lib/my_app/member.ex", 19},
      cond_unmatched: {"lib/my_app/member.ex", 21},
      destructured: {"lib/my_app/member.ex", 23},
      either: {"lib/my_app/member.ex", 25},
      four_ary: {"lib/my_app/member.ex", 27},
      if_strict: {"lib/my_app/member.ex", 29},
      invalid: {"lib/my_app/member.ex", 31},
      kind_unmatched: {"lib/my_app/member.ex", 33},
      listed: {"lib/my_app/member.ex", 35},
      narrowed: {"lib/my_app/member.ex", 37},
      no_such_field: {"lib/my_app/member.ex", 39},
      not_a_map: {"lib/my_app/member.ex", 41},
      outside: {"lib/my_app/member.ex", 43},
      same: {"lib/my_app/member.ex", 45},
      undefined: {"lib/my_app/member.ex", 47},
      wildcard_bound: {"lib/my_app/member.ex", 51},
      wildcard_invalid: {"lib/my_app/member.ex", 53},
      undefined_native: {"lib/my_app/member.ex", 55},
      undefined_inside_native: {"lib/my_app/member.ex", 57},
      not_a_module_target: {"lib/my_app/member.ex", 59},
      keyed_by_field: {"lib/my_app/member.ex", 61},
      keyed_read: {"lib/my_app/member.ex", 63},
      windowed: {"lib/my_app/member.ex", 49}
    }
  end
end
