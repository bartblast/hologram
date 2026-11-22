defmodule Hologram.Migration.Value.Check do
  @moduledoc false

  # What a file's backfills may not do: where one may be written, and whether its value suits the
  # member it fills. The renderer asks, so a pending file is refused before any file applies, and
  # a file already applied isn't judged again on every boot.

  alias Hologram.Entity.Model
  alias Hologram.Entity.Validator
  alias Hologram.Migration.Value
  alias Hologram.Migration.Value.Resolver

  # The largest integer a float holds exactly, as Resolver widens a literal.
  @max_exact_float_integer 9_007_199_254_740_992

  @bounded_types [:date, :datetime, :float, :integer, :time]

  @length_rules [:length, :max_length, :min_length]

  @doc """
  Validates the backfills of the given ops, one file's, against the model before them.

  A `change_attribute` or `change_relationship` may carry one only while turning an optional member
  required, with no type change. A to-many takes none, and a backfill is never nil. A computed one
  resolves against the model right before its op. A constant one must suit the member's type and
  its declared rules as they stand after the op, and fit the byte bound of any unique index over
  the member, at the op or later in the file, since the file builds those after it commits.

  Raises Hologram.CompileError naming the entity type, the member and the op's line.
  """
  @spec validate_ops!(list(%{atom => any}), %{atom => any}) :: :ok
  def validate_ops!(ops, pre_model) do
    final_model = Enum.reduce(ops, pre_model, &Model.fold_op(&2, &1))

    walk(ops, pre_model, final_model)
  end

  @doc """
  Validates that no fill among the given physical ops, one file's in order, uses an enum value an
  earlier op added to a type standing before it with ALTER TYPE: PostgreSQL refuses such a value
  until the transaction commits, so a copy would pass on an empty table and fail on real rows.

  Read from the physical ops because a logical add doesn't always add a value that way: a value
  arriving with its type is usable, as is one a rebuild has since carried into a new type.

  A column turning required takes its declared default the same way, but one in a file rendered
  in one piece only meets this on rows it has to fill, and applies on the others, so it's asked
  about only in a file with a cut: there a value that would have arrived with its type no longer
  does.

  Raises Hologram.CompileError naming the column or the fill's line, and the value.
  """
  @spec validate_enum_uses!(list(%{atom => any}), boolean) :: :ok
  def validate_enum_uses!(physical_ops, cut?) do
    checked =
      if cut?, do: physical_ops, else: Enum.reject(physical_ops, &Map.has_key?(&1, :fill))

    _added = Enum.reduce(checked, MapSet.new(), &track_enum_values/2)

    :ok
  end

  defp byte_bound(name, entry) do
    entry.attributes
    |> Validator.unique_string_max_bytes(entry.uniques)
    |> Map.get(name)
  end

  defp byte_refusal(value, op, later_ops, next_model, final_model) when is_binary(value) do
    at_op = byte_bound(op.name, next_model.entities[op.entity])

    at_end =
      op.entity
      |> final_member(op.name, later_ops)
      |> final_bound(final_model)

    bounds = Enum.reject([at_op, at_end], &is_nil/1)

    case bounds do
      [] ->
        nil

      _bounds ->
        max_bytes = Enum.min(bounds)

        if byte_size(value) > max_bytes, do: {:max_bytes, max_bytes}
    end
  end

  defp byte_refusal(_value, _op, _later_ops, _next_model, _final_model), do: nil

  # A declaration may bound a date or time in another calendar, so a bound needs only a calendar
  # the comparison can run on: a real one, with the day starting when ISO's does.
  defp comparable_bound?(%{__struct__: struct, calendar: calendar} = bound, type)
       when struct in [Date, DateTime, Time] do
    usable_calendar?(calendar) and integer_offsets?(bound) and
      Validator.attribute_value_valid?(bound, type)
  end

  defp comparable_bound?(%{__struct__: struct}, _type) when struct in [Date, DateTime, Time] do
    false
  end

  defp comparable_bound?(bound, type), do: Resolver.fits_type?(bound, type)

  defp compilable?(%Regex{}), do: true

  defp compilable?({:regex, source, opts}) when is_binary(source) and is_list(opts) do
    match?({:ok, _regex}, Regex.compile(source, opts))
  rescue
    # A bad pattern comes back as an error, a bad flag raises.
    ArgumentError -> false
  end

  defp compilable?(_format), do: false

  defp constant_refusal(value, {name, type, opts}, op, later_ops, next_model, final_model) do
    checked =
      value
      |> Value.normalize_constant(type)
      |> widen(type)

    cond do
      rule = unfit_rule(type, opts) ->
        {:unfit_rule, rule}

      not Resolver.storable?(checked) ->
        if Resolver.fits_type?(checked, type), do: :unstorable, else: {:type, type}

      true ->
        case Validator.value_errors(name, checked, type, runnable_opts(opts)) do
          [{^name, reason} | _rest] -> reason
          [] -> byte_refusal(checked, op, later_ops, next_model, final_model)
        end
    end
  end

  defp describe_refusal(_value, type, :unstorable) do
    "the database can't store as a #{inspect(type)}"
  end

  defp describe_refusal(_value, _type, {:type, _type_name} = reason) do
    Validator.requirement_description(reason)
  end

  defp describe_refusal(_value, type, reason) do
    "as a #{inspect(type)} #{Validator.requirement_description(reason)}"
  end

  defp final_bound(nil, _final_model), do: nil

  defp final_bound({entity, name}, final_model),
    do: byte_bound(name, final_model.entities[entity])

  # Where the given member ends up after the given ops, which may rename it or its entity type,
  # or nil once one deletes it: a later member under the same name is another column.
  defp final_member(entity, name, later_ops) do
    Enum.reduce_while(later_ops, {entity, name}, fn
      %{op: :delete_attribute, entity: op_entity, name: deleted}, {entity, name}
      when op_entity == entity and deleted == name ->
        {:halt, nil}

      %{op: :delete_entity, entity: deleted}, {entity, _name} when deleted == entity ->
        {:halt, nil}

      %{op: :rename_attribute, entity: op_entity, from: from, to: to}, {entity, name}
      when op_entity == entity and from == name ->
        {:cont, {entity, to}}

      %{op: :rename_entity, from: from, to: to}, {entity, name} when from == entity ->
        {:cont, {to, name}}

      _op, member ->
        {:cont, member}
    end)
  end

  # Read with Map.get/2 because a pinned struct may lack the fields.
  defp integer_offsets?(%{__struct__: DateTime} = bound) do
    is_integer(Map.get(bound, :std_offset)) and is_integer(Map.get(bound, :utc_offset))
  end

  defp integer_offsets?(_bound), do: true

  defp line(%{line: line}), do: " (line #{line})"

  defp line(_op), do: ""

  defp location(%{entity: entity, name: name} = op) do
    "the backfill of #{inspect(name)} on #{inspect(entity)}#{line(op)}"
  end

  defp optional?(%{entity: entity, name: name, op: op}, model) do
    list_key = if op == :change_attribute, do: :attributes, else: :relationships

    case List.keyfind(model.entities[entity][list_key], name, 0) do
      {_name, _type, opts} -> Keyword.get(opts, :optional, false) == true
      nil -> false
    end
  end

  @spec refuse!(%{atom => any}, String.t()) :: no_return
  defp refuse!(op, message) do
    raise Hologram.CompileError, message: "#{location(op)} #{message}"
  end

  # A rule the declaration would refuse for this type. An op's options aren't checked as a
  # declaration's are, and the validator's rule checks assume they were.
  defp rule_fits?({:format, format}, type), do: type == :string and compilable?(format)

  defp rule_fits?({key, value}, type) when key in @length_rules do
    type == :string and is_integer(value) and value >= 0
  end

  defp rule_fits?({:in, %Range{first: first, last: last, step: step}}, type) do
    type == :integer and is_integer(first) and is_integer(last) and is_integer(step) and step != 0
  end

  defp rule_fits?({:in, _value}, _type), do: false

  defp rule_fits?({key, bound}, :float) when key in [:max, :min], do: is_number(bound)

  defp rule_fits?({key, bound}, type) when key in [:max, :min] do
    type in @bounded_types and comparable_bound?(bound, type)
  end

  defp rule_fits?(_rule, _type), do: true

  # The model keeps a format as its pattern and flags, since a compiled regex compares unequal
  # from one read to the next. The validator takes it compiled.
  defp runnable_opts(opts) do
    case Keyword.fetch(opts, :format) do
      {:ok, {:regex, source, regex_opts}} ->
        Keyword.put(opts, :format, Regex.compile!(source, regex_opts))

      _no_stored_format ->
        opts
    end
  end

  defp track_enum_values(%{op: :add_enum_value} = op, added) do
    MapSet.put(added, {op.enum_type, op.value})
  end

  defp track_enum_values(%{op: :alter_column, fill: value} = op, added) do
    if MapSet.member?(added, {op.after.type, value}) do
      raise Hologram.CompileError,
        message:
          ~s(the default #{inspect(value)} of column "#{op.column}" on table "#{op.table}" is ) <>
            "an enum value this file adds to its type - PostgreSQL can't use a value in the " <>
            "transaction adding it (#1687), so move the change making the column required to " <>
            "the next migration file"
    end

    added
  end

  defp track_enum_values(%{op: :fill_column} = op, added) do
    case Enum.find(op.enum_uses, &MapSet.member?(added, &1)) do
      {_enum_type, value} ->
        refuse!(
          %{entity: op.entity, line: op.line, name: op.member},
          "uses the enum value #{inspect(value)}, which this file adds to its type - PostgreSQL " <>
            "can't use a value in the transaction adding it (#1687), so move the backfill to " <>
            "the next migration file"
        )

      nil ->
        added
    end
  end

  defp track_enum_values(%{op: kind, enum_type: enum_type}, added)
       when kind in [:drop_enum_type, :rebuild_enum_type] do
    added
    |> Enum.reject(fn {type, _value} -> type == enum_type end)
    |> MapSet.new()
  end

  defp track_enum_values(%{op: :rename_enum_type, from: from, to: to}, added) do
    MapSet.new(added, fn
      {^from, value} -> {to, value}
      pair -> pair
    end)
  end

  defp track_enum_values(%{op: :rename_enum_value, enum_type: type, from: from, to: to}, added) do
    MapSet.new(added, fn
      {^type, ^from} -> {type, to}
      pair -> pair
    end)
  end

  defp track_enum_values(_op, added), do: added

  defp unfit_rule(type, opts) do
    Enum.find(opts, &(not rule_fits?(&1, type)))
  end

  defp usable_calendar?(calendar) do
    is_atom(calendar) and Code.ensure_loaded?(calendar) and
      function_exported?(calendar, :valid_date?, 3) and
      function_exported?(calendar, :valid_time?, 4) and
      function_exported?(calendar, :naive_datetime_to_iso_days, 7) and
      function_exported?(calendar, :day_rollover_relative_to_midnight_utc, 0) and
      calendar.day_rollover_relative_to_midnight_utc() ==
        Calendar.ISO.day_rollover_relative_to_midnight_utc()
  end

  defp validate!(op, model, next_model, later_ops, final_model) do
    case Value.fetch_backfill(op) do
      {:ok, backfill} ->
        validate_present!(backfill, op)
        validate_tightening!(op, model, next_model)

        {kind, member} = Value.fill_member(op, next_model)

        validate_to_one!(kind, member, op)
        validate_value!(backfill, kind, member, op, model, next_model, later_ops, final_model)

      :error ->
        :ok
    end
  end

  defp validate_present!(nil, op) do
    refuse!(op, "is nil - a backfill is the value rows receive, so it needs one")
  end

  defp validate_present!(_backfill, _op), do: :ok

  defp validate_tightening!(%{op: kind, changes: changes} = op, model, next_model)
       when kind in [:change_attribute, :change_relationship] do
    if Keyword.has_key?(changes, :type) do
      refuse!(
        op,
        "sits beside a type change - change the type in an op of its own, since the fill would " <>
          "hold values of the new type while the column has the old one"
      )
    end

    if not optional?(op, model) and Keyword.get(changes, :optional) == false do
      refuse!(op, "fills a member that is already required, so no row holds nil")
    end

    if not optional?(op, model) or optional?(op, next_model) do
      refuse!(
        op,
        "fills the rows holding nil as the member turns required - add optional: false to " <>
          "the op, or remove the backfill"
      )
    end
  end

  defp validate_tightening!(_op, _model, _next_model), do: :ok

  defp validate_to_one!(:relationship, {_name, [_target], _opts}, op) do
    refuse!(op, "fills a to-many relationship - a backfill fills a value or a to-one reference")
  end

  defp validate_to_one!(_kind, _member, _op), do: :ok

  defp validate_value!(%Value{} = value, kind, member, op, model, _next, _later, _final) do
    Value.resolve!(value, model, op.entity, Value.fill_target(kind, member, op))

    :ok
  end

  defp validate_value!(
         value,
         :relationship,
         {_name, target, _opts},
         op,
         _model,
         _next,
         _later,
         _final
       ) do
    normalized = Value.normalize_constant(value, :uuid)

    if not Validator.attribute_value_valid?(normalized, :uuid) do
      refuse!(op, "holds #{inspect(value)}, which isn't the id of a #{inspect(target)}")
    end

    :ok
  end

  defp validate_value!(value, :attribute, member, op, _model, next_model, later_ops, final_model) do
    {_name, type, _opts} = member

    case constant_refusal(value, member, op, later_ops, next_model, final_model) do
      nil ->
        :ok

      {:unfit_rule, {key, rule_value}} ->
        refuse!(
          op,
          "fills an attribute declaring #{key}: #{inspect(rule_value)}, which a " <>
            "#{inspect(type)} attribute can't take"
        )

      reason ->
        refuse!(op, "holds #{inspect(value)}, which #{describe_refusal(value, type, reason)}")
    end
  end

  defp walk([], _model, _final_model), do: :ok

  defp walk([op | later_ops], model, final_model) do
    next_model = Model.fold_op(model, op)

    validate!(op, model, next_model, later_ops, final_model)

    walk(later_ops, next_model, final_model)
  end

  defp widen(value, :float) when is_integer(value) and abs(value) <= @max_exact_float_integer do
    value * 1.0
  end

  defp widen(value, _type), do: value
end
