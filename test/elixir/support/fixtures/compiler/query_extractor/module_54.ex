# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54 do
  # Stands for an entity type whose derived fields call query builders, most of which the build
  # cannot follow, at locations the refusals name. The definitions read the fields of entity types
  # that compile.

  alias Hologram.Entity.Derived
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53
  alias Hologram.Test.Fixtures.Entity.Module34
  alias Hologram.Test.Fixtures.Entity.Module36

  # The definitions hand fields of the row to builders that cannot take them, which is what the
  # walk refuses - so their calls fail on purpose.
  @dialyzer {:nowarn_function, __derived_definition__: 1}

  def __derived_definition__(:branched) do
    last_read_at = Derived.field(Module36, [:last_read_at])

    Module36
    |> Derived.field([:channel])
    |> Module53.by_flag(last_read_at)
    |> Derived.lower()
  end

  def __derived_definition__(:capitalized) do
    Module34
    |> Derived.field([:nickname])
    |> Module53.capitalized()
    |> Derived.lower()
  end

  def __derived_definition__(:constant) do
    Derived.lower(Module53.constant())
  end

  def __derived_definition__(:counted) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module53.message_total()
    |> Derived.lower()
  end

  def __derived_definition__(:dispatched) do
    last_read_at = Derived.field(Module36, [:last_read_at])

    Module36
    |> Derived.field([:channel, :messages])
    |> Module53.recent_or_all(last_read_at)
    |> Derived.lower()
  end

  def __derived_definition__(:dotted) do
    Module34
    |> Derived.field([:nickname])
    |> Module53.length_of()
    |> Derived.lower()
  end

  def __derived_definition__(:either_way) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module53.either_way(:all)
    |> Derived.lower()
  end

  def __derived_definition__(:forked) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module53.recent_or_all(:recent)
    |> Derived.lower()
  end

  def __derived_definition__(:looping) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module53.looping()
    |> Derived.lower()
  end

  def __derived_definition__(:missing) do
    Module36
    |> Derived.field([:member])
    |> Module53.missing()
    |> Derived.lower()
  end

  def __derived_definition__(:senders) do
    Module36
    |> Derived.field([:channel])
    |> Module53.senders()
    |> Derived.lower()
  end

  def __derived_locations__ do
    %{
      branched: {"lib/my_app/member.ex", 7},
      capitalized: {"lib/my_app/member.ex", 9},
      constant: {"lib/my_app/member.ex", 11},
      counted: {"lib/my_app/member.ex", 13},
      dispatched: {"lib/my_app/member.ex", 15},
      dotted: {"lib/my_app/member.ex", 17},
      either_way: {"lib/my_app/member.ex", 19},
      forked: {"lib/my_app/member.ex", 21},
      looping: {"lib/my_app/member.ex", 23},
      missing: {"lib/my_app/member.ex", 25},
      senders: {"lib/my_app/member.ex", 27}
    }
  end
end
