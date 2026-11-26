defmodule Hologram.Migration.Value.Resolver do
  @moduledoc false

  # Judges a lowered backfill against the model at its op: what each name reads there, and whether
  # the types fit. An executor then needs no model to know a value's type, since the resolved term
  # carries it. An enum's type names the attribute it belongs to, because PostgreSQL gives each
  # enum attribute a type of its own, so two enums holding the same values still differ.

  alias Hologram.DB.Codec
  alias Hologram.Entity
  alias Hologram.Entity.Validator
  alias Hologram.Migration.Value
  alias Hologram.Migration.Value.Check

  @type type ::
          :boolean
          | :date
          | :datetime
          | :float
          | :id
          | :integer
          | :string
          | :time
          | :uuid
          | {:enum, module, atom, list(atom)}
          | {:reference, module}

  @type target :: %{
          required(:kind) => :attribute | :relationship,
          required(:line) => pos_integer,
          required(:name) => atom,
          required(:type) => atom | module,
          optional(:opts) => keyword
        }

  @type resolved_set :: {:relationship, list(atom)} | {:referencing, module, atom}

  @type resolved ::
          {:function, module, atom, list(atom), type}
          | {:value, any, type}
          | {:name, list(atom), type}
          | {:concat, list(resolved)}
          | {:at, {:split, resolved, {:value, String.t(), :string}}, {:value, integer, :integer}}
          | {:coalesce, list(resolved)}
          | {:count, resolved_set}
          | {:most_common, resolved_set, atom, type, list(atom) | :characters | nil}

  # The dates and datetimes a column holds. The floor is PostgreSQL's, 4714 BC in its calendar.
  # The driver wraps a date past the top to another one with no error, and the codec can't encode
  # a datetime past it. Elixir's own range is wider on both sides.
  @max_date Date.new!(5_874_897, 12, 31)
  @max_datetime ~U[9999-12-31 23:59:59.999999Z]
  @min_date ~D[-4713-11-24]
  @min_datetime ~U[-4713-11-24 00:00:00Z]

  @time_types [:date, :datetime, :time]

  # The largest integer of the largest float, above which the conversion raises.
  @max_float_integer trunc(:math.pow(2, 1023) * (2 - :math.pow(2, -52)))

  @doc """
  Resolves the given backfill against the given model, the one standing right before the op, for
  the given member of the given entity type. Returns the term with each value's type embedded, and
  the type of its result.

  Raises Hologram.CompileError, naming the entity type, the member and the op's line, on a name the
  model doesn't have there, a to-one read by its own name, a set that isn't a stored to-many, a
  value that doesn't fit its type, and a result of another type than the member's.
  """
  @spec resolve!(Value.t(), %{atom => any}, module, target) :: %{term: resolved, type: type}
  def resolve!(%Value{term: term} = value, model, entity_type, target) do
    args = Map.get(value, :args, [])

    context = %{
      entity: entity_type,
      in_fn: args != [],
      line: target.line,
      member: target.name,
      model: model
    }

    validate_args!(args, context)

    expected = target_type(target, entity_type)

    {resolved, type} = resolve_term(term, expected, context)

    check_fits!(type, expected, context)

    %{term: resolved, type: type}
  end

  @doc """
  Returns the type the codec stores a value of the given resolved type as.
  """
  @spec codec_type(type) :: atom
  def codec_type({:enum, _owner, _name, _values}), do: :enum

  def codec_type({:reference, _target}), do: :id

  def codec_type(type), do: type

  @doc """
  Returns the float holding exactly the given integer, or nil when none does.
  """
  @spec exact_float(integer) :: float | nil
  def exact_float(integer) when is_integer(integer) and abs(integer) <= @max_float_integer do
    float = integer * 1.0

    if trunc(float) == integer, do: float
  end

  def exact_float(integer) when is_integer(integer), do: nil

  @doc """
  Returns whether PostgreSQL can store the given value, which `of_type?/2` accepted, in a column of
  its type.
  """
  @spec storable?(any) :: boolean
  def storable?(%Date{} = date) do
    well_formed?(date, :date) and Date.compare(date, @min_date) != :lt and
      Date.compare(date, @max_date) != :gt
  end

  def storable?(%DateTime{} = datetime) do
    well_formed?(datetime, :datetime) and DateTime.compare(datetime, @min_datetime) != :lt and
      DateTime.compare(datetime, @max_datetime) != :gt
  end

  def storable?(%Time{} = time), do: well_formed?(time, :time)

  def storable?(value) when is_binary(value), do: not String.contains?(value, <<0>>)

  def storable?(_value), do: true

  @doc """
  Returns whether the given value is of the given attribute type. Unlike the entity validator, it
  answers for a malformed date, datetime or time rather than calling a calendar the struct names,
  which a pinned value can make anything.
  """
  @spec fits_type?(any, atom) :: boolean
  def fits_type?(%{__struct__: struct} = value, type) when struct in [Date, DateTime, Time] do
    well_formed?(value, type)
  end

  def fits_type?(_value, :enum), do: false

  def fits_type?(value, type), do: of_type?(value, type)

  @doc """
  Returns whether the given value is of the given attribute type, other than an enum, with a date,
  datetime or time asked of the calendar it names. Unlike the entity validator, it leaves out what a column can
  store, which `storable?/1` answers, so a refusal can tell a value of the wrong type from one the
  database can't hold.
  """
  @spec of_type?(any, atom) :: boolean
  def of_type?(%Date{calendar: calendar, year: year, month: month, day: day}, :date)
      when is_integer(year) and is_integer(month) and is_integer(day) do
    calendar.valid_date?(year, month, day)
  end

  def of_type?(
        %DateTime{
          calendar: calendar,
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute,
          second: second,
          microsecond: {microsecond_amount, microsecond_precision} = microsecond
        },
        :datetime
      )
      when is_integer(year) and is_integer(month) and is_integer(day) and is_integer(hour) and
             is_integer(minute) and is_integer(second) and is_integer(microsecond_amount) and
             is_integer(microsecond_precision) do
    calendar.valid_date?(year, month, day) and
      calendar.valid_time?(hour, minute, second, microsecond)
  end

  def of_type?(
        %Time{
          calendar: calendar,
          hour: hour,
          minute: minute,
          second: second,
          microsecond: {microsecond_amount, microsecond_precision} = microsecond
        },
        :time
      )
      when is_integer(hour) and is_integer(minute) and is_integer(second) and
             is_integer(microsecond_amount) and is_integer(microsecond_precision) do
    calendar.valid_time?(hour, minute, second, microsecond)
  end

  def of_type?(_value, type) when type in @time_types, do: false

  def of_type?(value, :string), do: is_binary(value) and String.valid?(value)

  def of_type?(value, type), do: Validator.attribute_value_valid?(value, type)

  defp all_literal?({:value, _value}), do: true

  defp all_literal?({:coalesce, operands}), do: Enum.all?(operands, &all_literal?/1)

  defp all_literal?(_term), do: false

  defp attribute(entry, name), do: List.keyfind(entry.attributes, name, 0)

  defp attribute_type({name, :enum, opts}, owner) do
    {:enum, owner, name, Keyword.fetch!(opts, :values)}
  end

  defp attribute_type({_name, type, _opts}, _owner), do: type

  defp check_fits!(type, expected, context) do
    if not fits?(type, expected) do
      refuse!(context, "gives #{spell_type(type)} where #{spell_type(expected)} goes")
    end
  end

  # A row holds its related data under the relationship's name, so a field of that name would be
  # read as the related row. The model allows the pair mid-history, while a field is being
  # converted into a relationship.
  defp check_unambiguous!(name, owner, entry, context) do
    if relationship(entry, name) != nil and field?(entry, name) do
      refuse!(
        context,
        "reads through #{inspect(name)} of #{inspect(owner)}, which is both a relationship and " <>
          "a field at this op - rename one of them in an op above the backfill"
      )
    end
  end

  defp entry!(owner, context) do
    case context.model.entities do
      %{^owner => entry} -> entry
      _entities -> refuse!(context, "reads #{inspect(owner)}, which doesn't exist at this op")
    end
  end

  defp field?(entry, name) do
    attribute(entry, name) != nil or system_type(name) != nil or
      reference_target(entry, name) != nil
  end

  defp fit_uuid!(value, type, context) when is_binary(value) do
    lowercased = String.downcase(value)

    if Validator.attribute_value_valid?(lowercased, :uuid) do
      lowercased
    else
      refuse_value!(value, type, context)
    end
  end

  defp fit_uuid!(value, type, context), do: refuse_value!(value, type, context)

  # An integer where a float goes is a float. Everything else must already be of its type.
  defp fit_value!(nil, _type, context) do
    refuse!(context, "holds nil - nil is the absence a backfill exists to fill")
  end

  defp fit_value!(value, :float, context) when is_integer(value) do
    exact_float(value) || refuse_value!(value, :float, context)
  end

  defp fit_value!(value, :string, context) when is_binary(value) do
    if String.valid?(value) and storable?(value) do
      value
    else
      refuse_value!(value, :string, context)
    end
  end

  defp fit_value!(value, {:enum, _owner, _name, values} = type, context) do
    if is_atom(value) and value in values, do: value, else: refuse_value!(value, type, context)
  end

  defp fit_value!(value, {:reference, _target} = type, context) do
    if Validator.attribute_value_valid?(value, :id),
      do: value,
      else: refuse_value!(value, type, context)
  end

  defp fit_value!(value, :uuid, context), do: fit_uuid!(value, :uuid, context)

  defp fit_value!(value, type, context) do
    stored = Check.stored_form(value)

    if storable?(stored) and Validator.attribute_value_valid?(stored, type) do
      stored_form(stored, type)
    else
      refuse_value!(value, type, context)
    end
  end

  defp fits?(type, type), do: true

  defp fits?({:enum, _owner, _name, values}, {:enum, _target, _target_name, target_values}) do
    values -- target_values == []
  end

  defp fits?(_type, _expected), do: false

  # What to do instead of a path through a field: go through the relationship for a reference. A
  # date or time of the row itself has parts an Elixir fn can read, which a related row's doesn't,
  # since a fn names the row's own fields.
  defp hop_hint(hop, rest, owner, entry, kind, context) do
    cond do
      reference_target(entry, hop) ->
        relationship_name =
          hop
          |> Atom.to_string()
          |> String.replace_suffix("_id", "")

        ", so read through #{relationship_name}, not #{hop}"

      kind == :value and own_field?(hop, owner, context) and context.in_fn ->
        ", so read it in Elixir, like fn #{hop} -> Map.fetch!(#{hop}, #{inspect(hd(rest))}) end"

      kind == :value and own_field?(hop, owner, context) and time_field?(entry, hop) ->
        ", and a part of a date or time is read in a fn with Map.fetch!/2"

      true ->
        ""
    end
  end

  # What a name of the given owner reads. A reference reads as an id where an id goes, and an id
  # as a reference where a reference to its own type goes.
  defp name_type!(owner, [name], expected, context) do
    entry = entry!(owner, context)

    cond do
      member = attribute(entry, name) ->
        attribute_type(member, owner)

      name == :id ->
        if expected == {:reference, owner}, do: expected, else: :id

      system_type = system_type(name) ->
        system_type

      reference = reference_target(entry, name) ->
        if expected == :id, do: :id, else: {:reference, reference}

      relationship = relationship(entry, name) ->
        refuse_relationship_value!(relationship, owner, context)

      true ->
        refuse_unknown!(name, owner, entry, context)
    end
  end

  defp name_type!(owner, [hop | rest], expected, context) do
    entry = entry!(owner, context)

    check_unambiguous!(hop, owner, entry, context)

    case relationship(entry, hop) do
      {^hop, [_target], _opts} ->
        refuse!(
          context,
          "reads through #{inspect(hop)} of #{inspect(owner)}, a to-many - a path reads " <>
            "through to-one relationships"
        )

      {^hop, target, _opts} ->
        name_type!(target, rest, expected, context)

      nil ->
        refuse_hop!(hop, rest, owner, entry, :value, context)
    end
  end

  # A path's first name, read on the row itself. A later hop can carry the same name on another
  # type.
  defp own_field?(hop, owner, context) do
    owner == context.entity and hop == context[:path_head]
  end

  defp ranks({:enum, _owner, _name, values}), do: values

  # An id, a uuid or a reference orders by its characters, the way its column orders, rather than
  # as text, which folds the letter case an id reads apart.
  defp ranks({:reference, _target}), do: :characters

  defp ranks(type) when type in [:id, :uuid], do: :characters

  defp ranks(_type), do: nil

  defp reference_target(entry, name) do
    text = Atom.to_string(name)

    if String.ends_with?(text, "_id") do
      relationship_name = String.replace_suffix(text, "_id", "")

      entry.relationships
      |> Enum.find(fn {candidate, _type, _opts} ->
        Atom.to_string(candidate) == relationship_name
      end)
      |> to_one_target()
    end
  end

  @spec refuse!(%{atom => any}, String.t()) :: no_return
  defp refuse!(context, message) do
    raise Hologram.CompileError,
      message:
        "the backfill of #{inspect(context.member)} on #{inspect(context.entity)} " <>
          "(line #{context.line}) #{message}"
  end

  @spec refuse_hop!(atom, list(atom), module, %{atom => any}, :set | :value, %{atom => any}) ::
          no_return
  defp refuse_hop!(hop, rest, owner, entry, kind, context) do
    if field?(entry, hop) do
      refuse!(
        context,
        "reads through #{inspect(hop)} of #{inspect(owner)}, a field - a path reads through " <>
          "to-one relationships#{hop_hint(hop, rest, owner, entry, kind, context)}"
      )
    else
      refuse_unknown!(hop, owner, entry, context)
    end
  end

  @spec refuse_relationship_value!(tuple, module, %{atom => any}) :: no_return
  defp refuse_relationship_value!({name, [_target], _opts}, owner, context) do
    refuse!(
      context,
      "reads #{inspect(name)} of #{inspect(owner)}, a to-many, as a value - " <>
        "read it with count or most_common"
    )
  end

  defp refuse_relationship_value!({name, _target, _opts}, owner, context) do
    refuse!(
      context,
      "reads #{inspect(name)} of #{inspect(owner)}, a to-one, as a value - " <>
        "its reference is #{name}_id"
    )
  end

  @spec refuse_unknown!(atom, module, %{atom => any}, %{atom => any}) :: no_return
  defp refuse_unknown!(name, owner, entry, context) do
    member_names =
      [entry.attributes, entry.relationships, Entity.system_attributes()]
      |> Enum.concat()
      |> Enum.map(fn {name, _type, _opts} -> Atom.to_string(name) end)

    reference_names =
      for {relationship, target, _opts} <- entry.relationships, not is_list(target) do
        "#{relationship}_id"
      end

    names =
      member_names
      |> Enum.concat(reference_names)
      |> Enum.sort()
      |> Enum.join(", ")

    refuse!(
      context,
      "reads #{inspect(name)}, which #{inspect(owner)} doesn't have at this op - it has: #{names}"
    )
  end

  @spec refuse_value!(any, type, %{atom => any}) :: no_return
  defp refuse_value!(value, type, context) do
    refuse!(context, "holds #{Check.printed(value)}, which isn't #{spell_type(type)}")
  end

  defp relationship(entry, name), do: List.keyfind(entry.relationships, name, 0)

  # A literal waits for its siblings' type, and so does a coalesce holding only literals.
  defp resolve_coalesce_operand(operand, expected, context) do
    if all_literal?(operand) do
      {:literal, operand}
    else
      resolve_term(operand, expected, context)
    end
  end

  defp resolve_position!(n, context) do
    max_position = Value.max_position()

    if is_integer(n) and n in 0..max_position do
      n
    else
      refuse!(
        context,
        "reads position #{Check.printed(n)} - at takes an integer from 0 to #{max_position}"
      )
    end
  end

  defp resolve_separator!(separator, context) do
    if is_binary(separator) and separator != "" do
      fit_value!(separator, :string, context)
    else
      refuse!(context, "splits by #{Check.printed(separator)} - split takes a non-empty string")
    end
  end

  # The owner the set's rows belong to, its names being to-one hops and then a stored to-many.
  defp resolve_set!({:relationship, path}, context) do
    {{:relationship, path}, set_target!(context.entity, path, context)}
  end

  # The rows of the given type whose to-one points at this row. Nothing needs storing to reach
  # them, so the to-one has to say so itself.
  defp resolve_set!({:referencing, type, ref} = set, context) do
    entry = entry!(type, context)

    case relationship(entry, ref) do
      {^ref, target, _opts} when target == context.entity ->
        {set, type}

      {^ref, target, _opts} ->
        refuse!(
          context,
          "queries #{inspect(type)} by #{ref}_id, which points at #{inspect(target)}, not at " <>
            "#{inspect(context.entity)}"
        )

      nil ->
        refuse!(
          context,
          "queries #{inspect(type)} by #{ref}_id, but #{inspect(type)} has no to-one #{ref} at " <>
            "this op"
        )
    end
  end

  # What it returns is known only when it runs, so the apply checks its type then.
  defp resolve_term({:function, module, function, args}, expected, context) do
    entry = entry!(context.entity, context)

    Enum.each(args, fn arg ->
      if not field?(entry, arg) do
        refuse!(
          context,
          "takes #{inspect(arg)}, a relationship, in an Elixir fn - an Elixir fn reads the " <>
            "row's own fields, so read it through a query word instead"
        )
      end
    end)

    {{:function, module, function, args, expected}, expected}
  end

  defp resolve_term({:value, value}, expected, context) do
    {{:value, fit_value!(value, expected, context), expected}, expected}
  end

  defp resolve_term({:name, path}, expected, context) do
    type = name_type!(context.entity, path, expected, Map.put(context, :path_head, hd(path)))

    {{:name, path, type}, type}
  end

  defp resolve_term({:concat, operands}, _expected, context) do
    resolved =
      Enum.map(operands, fn operand ->
        {resolved_operand, type} = resolve_term(operand, :string, context)

        check_fits!(type, :string, context)

        resolved_operand
      end)

    {{:concat, resolved}, :string}
  end

  defp resolve_term({:at, {:split, text, {:value, separator}}, {:value, position}}, _exp, context) do
    {resolved_text, text_type} = resolve_term(text, :string, context)

    check_fits!(text_type, :string, context)

    split = {:split, resolved_text, {:value, resolve_separator!(separator, context), :string}}

    {{:at, split, {:value, resolve_position!(position, context), :integer}}, :string}
  end

  # The values of a coalesce share one type. A literal takes its siblings' type, since the
  # database compares it with them, and the target's when it has no sibling to take it from.
  defp resolve_term({:coalesce, operands}, expected, context) do
    first_pass = Enum.map(operands, &resolve_coalesce_operand(&1, expected, context))

    types = for {resolved, type} <- first_pass, resolved != :literal, do: type
    shared_type = List.first(types, expected)

    if Enum.any?(types, &(&1 != shared_type)) do
      mismatch = Enum.find(types, &(&1 != shared_type))

      refuse!(
        context,
        "mixes #{spell_type(shared_type)} and #{spell_type(mismatch)} in coalesce - " <>
          "its values share one type"
      )
    end

    resolved =
      Enum.map(first_pass, fn
        {:literal, literal} ->
          {resolved_literal, _type} = resolve_term(literal, shared_type, context)
          resolved_literal

        {resolved_operand, _type} ->
          resolved_operand
      end)

    {{:coalesce, resolved}, shared_type}
  end

  defp resolve_term({:count, set}, _expected, context) do
    {resolved_set, _target} = resolve_set!(set, context)

    {{:count, resolved_set}, :integer}
  end

  defp resolve_term({:most_common, set, attribute}, expected, context) do
    {resolved_set, target} = resolve_set!(set, context)
    type = name_type!(target, [attribute], expected, context)

    if type == :float do
      refuse!(
        context,
        "reads #{inspect(attribute)} with most_common, a float - the database groups 0.0 " <>
          "with -0.0, so the most common float isn't well defined"
      )
    end

    {{:most_common, resolved_set, attribute, type, ranks(type)}, type}
  end

  defp set_target!(owner, [name], context) do
    entry = entry!(owner, context)

    check_unambiguous!(name, owner, entry, context)

    case relationship(entry, name) do
      {^name, [target], _opts} ->
        target

      {^name, _target, _opts} ->
        refuse!(
          context,
          "counts or groups #{inspect(name)} of #{inspect(owner)}, a to-one - " <>
            "a set is a stored to-many"
        )

      nil ->
        if field?(entry, name) do
          refuse!(
            context,
            "reads #{inspect(name)} of #{inspect(owner)}, a field, as a set - " <>
              "a set is a stored to-many"
          )
        else
          refuse_unknown!(name, owner, entry, context)
        end
    end
  end

  defp set_target!(owner, [hop | rest], context) do
    entry = entry!(owner, context)

    check_unambiguous!(hop, owner, entry, context)

    case relationship(entry, hop) do
      {^hop, [_target], _opts} ->
        refuse!(
          context,
          "reads through #{inspect(hop)} of #{inspect(owner)}, a to-many - a path reads " <>
            "through to-one relationships"
        )

      {^hop, target, _opts} ->
        set_target!(target, rest, context)

      nil ->
        refuse_hop!(hop, rest, owner, entry, :set, context)
    end
  end

  defp spell_type({:enum, owner, name, _values}) do
    "the enum #{inspect(name)} of #{inspect(owner)}"
  end

  defp spell_type({:reference, target}), do: "a reference to #{inspect(target)}"

  defp spell_type(type), do: "a value of type #{inspect(type)}"

  # A datetime in UTC and a time at microsecond precision, as the database gives them back, so a
  # value here compares equal to the same value read from a column.
  defp stored_form(value, type) when type in [:datetime, :time], do: Codec.encode(value, type)

  defp stored_form(value, _type), do: value

  defp system_type(name) do
    case List.keyfind(Entity.system_attributes(), name, 0) do
      {^name, type, _opts} -> type
      nil -> nil
    end
  end

  defp target_type(%{kind: :attribute, name: name, type: :enum, opts: opts}, entity_type) do
    {:enum, entity_type, name, Keyword.fetch!(opts, :values)}
  end

  defp target_type(%{kind: :attribute, type: type}, _entity_type), do: type

  defp target_type(%{kind: :relationship, type: target}, _entity_type), do: {:reference, target}

  defp time_field?(entry, name) do
    type =
      case attribute(entry, name) do
        {_name, attribute_type, _opts} -> attribute_type
        nil -> system_type(name)
      end

    type in @time_types
  end

  defp to_one_target({_name, target, _opts}) when not is_list(target), do: target

  defp to_one_target(_relationship), do: nil

  defp validate_args!(args, context) do
    entry = entry!(context.entity, context)

    Enum.each(args, fn arg ->
      if not field?(entry, arg) and relationship(entry, arg) == nil do
        refuse_unknown!(arg, context.entity, entry, context)
      end
    end)
  end

  # A pinned struct may hold anything. The calendar is read first because the validator calls it,
  # and a datetime's offsets because comparing one does arithmetic on them.
  defp well_formed?(
         %DateTime{calendar: Calendar.ISO, std_offset: std_offset, utc_offset: utc_offset} = value,
         type
       )
       when is_integer(std_offset) and is_integer(utc_offset) do
    of_type?(value, type)
  end

  defp well_formed?(%DateTime{}, _type), do: false

  defp well_formed?(%{calendar: Calendar.ISO} = value, type), do: of_type?(value, type)

  defp well_formed?(_value, _type), do: false
end
