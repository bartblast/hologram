defmodule Hologram.Migration.Value.Check do
  @moduledoc false

  # What a file's backfills may not do: where one may be written, and whether its value suits the
  # member it fills. The renderer asks, so a pending file is refused before any file applies, and
  # a file already applied isn't judged again on every boot.

  alias Hologram.Entity.Model
  alias Hologram.Entity.Validator
  alias Hologram.Migration.Value
  alias Hologram.Migration.Value.Resolver

  @bounded_types [:date, :datetime, :float, :integer, :time]

  @length_rules [:length, :max_length, :min_length]

  @iso_values %{
    Date => ~D[2000-01-01],
    DateTime => ~U[2000-01-01 00:00:00Z],
    Time => ~T[00:00:00]
  }

  @doc """
  Validates the backfills of the given ops, one file's, against the model before them.

  A `change_attribute` or `change_relationship` may carry one only while turning an optional member
  required, with no type change. A to-many takes none, and a backfill is never nil. A computed one
  resolves against the model right before its op. A constant one must suit the member's type and
  its declared rules as they stand after the op, and fit the byte bound of any unique index over
  the member standing while it fills - one the table had before the file - and, unless a later op
  changes the member's type, converting the value, of any the file leaves, which it builds after
  it commits.

  An op stating an attribute's type or default must also leave it a default that suits the type,
  since a later fill would otherwise crash encoding it.

  Raises Hologram.CompileError naming the entity type, the member and the op's line.
  """
  @spec validate_ops!(list(%{atom => any}), %{atom => any}) :: :ok
  def validate_ops!(ops, pre_model) do
    final_model = Enum.reduce(ops, pre_model, &Model.fold_op(&2, &1))

    walk(ops, pre_model, file_keys(pre_model), final_model)
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

  Validates as well that the value an added column is filled with is one its type holds there: a
  file that adds a member with a backfill and then deletes that value from its type in the same
  chunk creates the type without it, so the fill would fail on every row. A tightening's backfill
  has a chunk of its own, and a declared default its type doesn't hold yet is asked about where it
  fills rows (see Hologram.DB.Preflight.check_fill!/1).

  Raises Hologram.CompileError naming the column or the fill's line, and the value.
  """
  @spec validate_enum_uses!(list(%{atom => any}), boolean) :: :ok
  def validate_enum_uses!(physical_ops, cut?) do
    checked =
      if cut?, do: physical_ops, else: Enum.reject(physical_ops, &Map.has_key?(&1, :fill))

    _added = Enum.reduce(checked, MapSet.new(), &track_enum_values/2)
    _held = Enum.reduce(physical_ops, %{}, &track_held_values/2)

    :ok
  end

  @doc """
  Returns the given ops, one file's, with each computed fill of an attribute carrying :max_bytes,
  the most its value may hold so that the unique indexes over the attribute can carry it, or nil
  with none: the ones standing while it fills, which the table had before the file, and the ones
  the file leaves, unless a later op changes the attribute's type, converting the value.
  """
  @spec put_byte_bounds(list(%{atom => any}), %{atom => any}) :: list(%{atom => any})
  def put_byte_bounds(ops, pre_model) do
    final_model = Enum.reduce(ops, pre_model, &Model.fold_op(&2, &1))

    bound_ops(ops, pre_model, file_keys(pre_model), final_model)
  end

  @doc """
  Returns the given declared options with a stored format compiled, as the validator takes it.
  """
  @spec runnable_opts(keyword) :: keyword
  # The pattern is the one the app's own entity type or migration declares, never a request's.
  # sobelow_skip ["DOS.Regex"]
  def runnable_opts(opts) do
    case Keyword.fetch(opts, :format) do
      {:ok, {:regex, source, regex_opts}} ->
        Keyword.put(opts, :format, Regex.compile!(source, regex_opts))

      _no_stored_format ->
        opts
    end
  end

  @doc """
  Returns the given value as a column stores it: a datetime in another calendar that compares with
  ISO becomes the same moment in UTC ISO, and anything else, including an ISO datetime at an
  offset, stays as it is.
  """
  @spec stored_form(any) :: any
  def stored_form(%DateTime{calendar: calendar} = value) when calendar != Calendar.ISO do
    with true <- comparable_bound?(value, :datetime),
         unix = DateTime.to_unix(value, :microsecond),
         {:ok, iso} <- DateTime.from_unix(unix, :microsecond) do
      iso
    else
      _unusable -> value
    end
  catch
    # A pinned value can name any module as its calendar, so one that fails is just unusable.
    _kind, _reason -> value
  end

  def stored_form(value), do: value

  @doc """
  Returns the given value printed for a refusal.
  """
  @spec printed(any) :: String.t()
  def printed(value) do
    inspect(value, safe: false)
  catch
    # A value can name any module as its calendar, and one that fails while printing the value
    # mustn't hide the refusal, or bury it in the error's text, so the struct is printed as a plain
    # map.
    _kind, _reason -> inspect(value, structs: false)
  end

  @doc """
  Returns what the given violation reason requires of a value, as
  Validator.requirement_description/1 says it, with a bound printed for a refusal.
  """
  @spec requirement_description({atom, any}) :: String.t()
  def requirement_description({:max, max}), do: "must be at most #{printed(max)}"

  def requirement_description({:min, min}), do: "must be at least #{printed(min)}"

  def requirement_description(reason), do: Validator.requirement_description(reason)

  defp attribute_type({entity, name}, model) do
    case List.keyfind(model.entities[entity].attributes, name, 0) do
      {_name, type, _opts} -> type
      nil -> nil
    end
  end

  defp bound_ops([], _model, _keys, _final_model), do: []

  defp bound_ops([op | later_ops], model, keys, final_model) do
    bounds = op_bounds(op, later_ops, model, keys, final_model)

    [
      put_byte_bound(op, bounds)
      | bound_ops(later_ops, bounds.next_model, bounds.keys, final_model)
    ]
  end

  defp byte_bound(name, entry) do
    entry.attributes
    |> Validator.unique_string_max_bytes(entry.uniques)
    |> Map.get(name)
  end

  defp byte_refusal(value, op, bounds) when is_binary(value) do
    case max_bytes(op, bounds) do
      nil -> nil
      bound -> if byte_size(value) > bound, do: {:max_bytes, bound}
    end
  end

  defp byte_refusal(_value, _op, _bounds), do: nil

  # A declaration may bound a date or time in another calendar, so a bound needs only a calendar
  # the comparison can run on: a real one, with the day starting when ISO's does for a date or
  # datetime, which compare by their ISO days. Times compare by their day fraction alone.
  defp comparable_bound?(%{__struct__: struct, calendar: calendar} = bound, type)
       when struct in [Date, DateTime, Time] do
    # The rules compare the value with the bound, which runs calendar functions the checks before
    # don't, and one value in ISO makes the comparison convert the bound.
    usable_calendar?(calendar, struct) and integer_offsets?(bound) and
      Resolver.of_type?(bound, type) and
      struct.compare(bound, Map.fetch!(@iso_values, struct)) in [:eq, :gt, :lt]
  catch
    # A declared bound can name any module as its calendar, so one that fails can't be compared.
    _kind, _reason -> false
  end

  defp comparable_bound?(%{__struct__: struct}, _type) when struct in [Date, DateTime, Time] do
    false
  end

  defp comparable_bound?(bound, type), do: Resolver.fits_type?(bound, type)

  defp compilable?(%Regex{}), do: true

  # The pattern is the one the app's own entity type or migration declares, never a request's.
  # sobelow_skip ["DOS.Regex"]
  defp compilable?({:regex, source, opts}) when is_binary(source) and is_list(opts) do
    match?({:ok, _regex}, Regex.compile(source, opts))
  rescue
    # A bad pattern comes back as an error, a bad flag raises.
    ArgumentError -> false
  end

  defp compilable?(_format), do: false

  defp constant_refusal(value, {name, type, opts}, op, bounds) do
    checked = Value.normalize_constant(value, type)

    cond do
      rule = unfit_rule(type, opts) ->
        {:unfit_rule, rule}

      not Resolver.storable?(checked) ->
        if Resolver.fits_type?(checked, type), do: :unstorable, else: {:type, type}

      true ->
        case Validator.value_errors(name, checked, type, runnable_opts(opts)) do
          [{^name, reason} | _rest] -> reason
          [] -> byte_refusal(checked, op, bounds)
        end
    end
  end

  # An enum is asked about its values at the file's end too, since a generated file changes the
  # default above the op adding the value. A rule the type can't take is left to the declaration,
  # since the validator can't run it, and the others still apply.
  defp default_refusal(default, {_name, :enum, opts}, op, bounds) do
    values = Keyword.fetch!(opts, :values)

    if default not in (values ++ final_enum_values(op, bounds)) do
      {:values, values}
    end
  end

  defp default_refusal(default, {name, type, opts}, op, bounds) do
    checked = widen(default, type)
    stored = stored_form(checked)

    cond do
      not Resolver.storable?(stored) ->
        if Resolver.fits_type?(checked, type), do: :unstorable, else: {:type, type}

      not Validator.attribute_value_valid?(checked, type) ->
        {:type, type}

      true ->
        runnable =
          opts
          |> Enum.filter(&rule_fits?(&1, type))
          |> runnable_opts()

        case Validator.value_errors(name, checked, type, runnable) do
          [{^name, reason} | _rest] -> reason
          [] -> byte_refusal(checked, op, bounds)
        end
    end
  end

  defp describe_refusal(_value, type, :unstorable) do
    "the database can't store as a #{inspect(type)}"
  end

  defp describe_refusal(_value, _type, {:type, _type_name} = reason) do
    requirement_description(reason)
  end

  defp describe_refusal(_value, type, reason) do
    "as a #{inspect(type)} #{requirement_description(reason)}"
  end

  # The unique keys each entity type's table has before the file, as follow_keys/2 takes them.
  defp file_keys(model) do
    for {entity, entry} <- model.entities,
        fields <-
          Enum.concat(
            for({name, _type, opts} <- entry.attributes, opts[:unique] == true, do: [name]),
            entry.uniques
          ),
        into: MapSet.new(),
        do: {entity, Enum.sort(fields)}
  end

  defp fill_word(%{fill_source: :backfill}), do: "backfill"

  defp fill_word(_op), do: "default"

  defp final_bound(nil, _final_model), do: nil

  defp final_bound({entity, name}, final_model),
    do: byte_bound(name, final_model.entities[entity])

  defp final_enum_values(op, %{final_model: final_model, later_ops: later_ops}) do
    with {entity, name} <- final_member(op.entity, op.name, later_ops),
         {_name, :enum, opts} <- List.keyfind(final_model.entities[entity].attributes, name, 0) do
      Keyword.fetch!(opts, :values)
    else
      _gone_or_not_enum -> []
    end
  end

  # Where the given member ends up after the given ops, which may rename it or its entity type,
  # or nil once one deletes it: a later member under the same name is another column.
  defp final_member(entity, name, later_ops) do
    Enum.reduce_while(later_ops, {entity, name}, &follow_member/2)
  end

  # Where the unique keys the table had before the file go as the given op renames or deletes
  # their fields or their entity type, each as its entity type and its fields sorted.
  defp follow_keys(keys, %{op: :rename_entity, from: from, to: to}) do
    MapSet.new(keys, fn
      {^from, fields} -> {to, fields}
      key -> key
    end)
  end

  defp follow_keys(keys, %{op: kind, entity: entity, from: from, to: to})
       when kind in [:rename_attribute, :rename_relationship] do
    MapSet.new(keys, fn
      {^entity, fields} ->
        {entity, Enum.sort(Enum.map(fields, &if(&1 == from, do: to, else: &1)))}

      key ->
        key
    end)
  end

  defp follow_keys(keys, %{op: kind, entity: entity, name: name})
       when kind in [:delete_attribute, :delete_relationship] do
    MapSet.reject(keys, fn {key_entity, fields} -> key_entity == entity and name in fields end)
  end

  defp follow_keys(keys, %{op: :delete_entity, entity: entity}) do
    MapSet.reject(keys, &match?({^entity, _fields}, &1))
  end

  defp follow_keys(keys, _op), do: keys

  defp follow_member(%{op: :delete_attribute, entity: entity, name: name}, {entity, name}),
    do: {:halt, nil}

  defp follow_member(%{op: :delete_entity, entity: entity}, {entity, _name}), do: {:halt, nil}

  defp follow_member(
         %{op: :rename_attribute, entity: entity, from: name, to: to},
         {entity, name}
       ),
       do: {:cont, {entity, to}}

  defp follow_member(%{op: :rename_entity, from: entity, to: to}, {entity, name}),
    do: {:cont, {to, name}}

  defp follow_member(_op, member), do: {:cont, member}

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

  # The indexes standing while the fill runs bound what it writes. The ones the file builds after
  # it commits hold the member as the file leaves it, so they bound the fill only while no later
  # op changes the member's type, converting what the fill wrote.
  defp max_bytes(op, bounds) do
    %{final_model: final_model, keys: keys, later_ops: later_ops, next_model: next_model} = bounds

    at_op = byte_bound(op.name, standing_entry(next_model.entities[op.entity], op.entity, keys))

    at_end =
      if retyped_later?(op, later_ops, next_model) do
        nil
      else
        op.entity
        |> final_member(op.name, later_ops)
        |> final_bound(final_model)
      end

    case Enum.reject([at_op, at_end], &is_nil/1) do
      [] -> nil
      bounds -> Enum.min(bounds)
    end
  end

  defp op_bounds(op, later_ops, model, keys, final_model) do
    %{
      final_model: final_model,
      keys: follow_keys(keys, op),
      later_ops: later_ops,
      next_model: Model.fold_op(model, op)
    }
  end

  defp optional?(op, model) do
    case member(op, model) do
      {_name, _type, opts} -> Keyword.get(opts, :optional, false) == true
      nil -> false
    end
  end

  defp member(%{entity: entity, name: name, op: op}, model) do
    list_key = if op == :change_attribute, do: :attributes, else: :relationships

    List.keyfind(model.entities[entity][list_key], name, 0)
  end

  defp member_type(op, model) do
    case member(op, model) do
      {_name, type, _opts} -> type
      nil -> nil
    end
  end

  defp put_byte_bound(%{op: kind} = op, bounds)
       when kind in [:add_attribute, :change_attribute] do
    case Value.fetch_backfill(op) do
      {:ok, %Value{}} ->
        Map.put(op, :max_bytes, max_bytes(op, bounds))

      _constant_or_none ->
        op
    end
  end

  defp put_byte_bound(op, _bounds), do: op

  @spec refuse!(%{atom => any}, String.t()) :: no_return
  defp refuse!(op, message) do
    raise Hologram.CompileError, message: "#{location(op)} #{message}"
  end

  @spec refuse_unfit_rule!(%{atom => any}, {atom, any}, any) :: no_return
  defp refuse_unfit_rule!(op, {key, rule_value}, type) do
    refuse!(
      op,
      "fills an attribute declaring #{key}: #{printed(rule_value)}, which a " <>
        "#{inspect(type)} attribute can't take"
    )
  end

  defp retyped_later?(op, later_ops, model) do
    member = {op.entity, op.name}

    retyped_later?(member, attribute_type(member, model), later_ops, model)
  end

  defp retyped_later?(_member, _type, [], _model), do: false

  defp retyped_later?(member, type, [later_op | rest], model) do
    next_model = Model.fold_op(model, later_op)

    case follow_member(later_op, member) do
      {:halt, nil} ->
        false

      {:cont, next_member} ->
        attribute_type(next_member, next_model) != type or
          retyped_later?(next_member, type, rest, next_model)
    end
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

  # The given entity type's entry with only the unique keys standing while a fill runs: the file
  # builds a key it adds after it commits, on a table standing before it. A key the table had
  # counts even when the file drops it and adds it back, since a chunk doing both over the same
  # fields in the same order leaves its index standing. Across chunks, or in another order, the
  # index drops before the fill, which then gets bound more than it has to, never less. A table
  # born in the file has no rows to fill.
  defp standing_entry(entry, entity, keys) do
    attributes =
      Enum.map(entry.attributes, fn {name, type, opts} = attribute ->
        if opts[:unique] == true and not MapSet.member?(keys, {entity, [name]}),
          do: {name, type, Keyword.delete(opts, :unique)},
          else: attribute
      end)

    uniques = Enum.filter(entry.uniques, &MapSet.member?(keys, {entity, Enum.sort(&1)}))

    %{entry | attributes: attributes, uniques: uniques}
  end

  defp track_enum_values(%{op: :add_enum_value} = op, added) do
    MapSet.put(added, {op.enum_type, op.value})
  end

  defp track_enum_values(%{op: :alter_column, fill: value} = op, added) do
    if MapSet.member?(added, {op.after.type, value}) do
      raise Hologram.CompileError,
        message:
          ~s(the #{fill_word(op)} #{printed(value)} of column "#{op.column}" on table ) <>
            ~s("#{op.table}" is ) <>
            "an enum value this file adds to its type - PostgreSQL can't use a value in the " <>
            "transaction adding it (#1687), so move the change making the column required to " <>
            "the next migration file, under the names things have there"
    end

    added
  end

  defp track_enum_values(%{op: :fill_column} = op, added) do
    case Enum.find(op.enum_uses, &MapSet.member?(added, &1)) do
      {_enum_type, value} ->
        refuse!(
          %{entity: op.entity, line: op.line, name: op.member},
          "uses the enum value #{inspect(value)}, which this file adds to its type - PostgreSQL " <>
            "can't use a value in the transaction adding it (#1687), so move #{filling_op(op)}, " <>
            "with its backfill, to the next migration file, under the names things have there"
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

  # A backfill can't stand on its own, so the op carrying it moves.
  defp filling_op(%{nulls_only: true}), do: "the op making the member required"

  defp filling_op(_fill), do: "the op adding the member"

  # The values of each enum type the file creates or rebuilds, as the ops so far leave them.
  defp track_held_values(%{op: kind, enum_type: type, values: values}, held)
       when kind in [:create_enum_type, :rebuild_enum_type] do
    Map.put(held, type, values)
  end

  defp track_held_values(%{op: :add_enum_value, enum_type: type, value: value}, held) do
    update_held(held, type, &[value | &1])
  end

  defp track_held_values(%{op: :rename_enum_value, enum_type: type, from: from, to: to}, held) do
    update_held(held, type, fn values -> Enum.map(values, &if(&1 == from, do: to, else: &1)) end)
  end

  defp track_held_values(%{op: :rename_enum_type, from: from, to: to}, held) do
    case Map.pop(held, from) do
      {nil, held} -> held
      {values, held} -> Map.put(held, to, values)
    end
  end

  defp track_held_values(%{op: :drop_enum_type, enum_type: type}, held),
    do: Map.delete(held, type)

  defp track_held_values(%{op: :add_column, backfill: value} = op, held) do
    validate_held!(held, op.definition.type, value, op)
  end

  defp track_held_values(_op, held), do: held

  defp update_held(held, type, fun) do
    if Map.has_key?(held, type), do: Map.update!(held, type, fun), else: held
  end

  defp validate_held!(held, type, value, op) do
    case Map.fetch(held, type) do
      {:ok, values} when is_binary(value) ->
        if value not in values do
          raise Hologram.CompileError,
            message:
              ~s(the value #{printed(value)} filling column "#{op.column}" on table ) <>
                ~s("#{op.table}" is an enum value this file deletes from its type, which no ) <>
                "longer holds it where the fill runs, so the fill would fail on every row - " <>
                "fill with a value the type keeps, or keep the value"
        end

        held

      _unknown_or_not_enum ->
        held
    end
  end

  defp unfit_rule(type, opts) do
    Enum.find(opts, &(not rule_fits?(&1, type)))
  end

  defp usable_calendar?(calendar, struct) do
    is_atom(calendar) and Code.ensure_loaded?(calendar) and
      function_exported?(calendar, :valid_date?, 3) and
      function_exported?(calendar, :valid_time?, 4) and
      function_exported?(calendar, :naive_datetime_to_iso_days, 7) and
      (struct == Time or iso_day_rollover?(calendar))
  end

  defp iso_day_rollover?(calendar) do
    function_exported?(calendar, :day_rollover_relative_to_midnight_utc, 0) and
      calendar.day_rollover_relative_to_midnight_utc() ==
        Calendar.ISO.day_rollover_relative_to_midnight_utc()
  end

  defp validate!(op, model, next_model, bounds) do
    validate_default!(op, next_model, bounds)

    case Value.fetch_backfill(op) do
      {:ok, backfill} ->
        validate_present!(backfill, op)
        validate_tightening!(op, model, next_model)

        {kind, member} = Value.fill_member(op, next_model)

        validate_to_one!(kind, member, op)
        validate_value!(backfill, kind, member, op, model, bounds)

      :error ->
        :ok
    end
  end

  # A default fills rows when a column turns required, so one its type can't hold would crash there,
  # possibly files later. Asked only of an op stating a type or a default.
  defp validate_default!(%{op: kind} = op, next_model, bounds)
       when kind in [:add_attribute, :change_attribute] do
    stated = if kind == :add_attribute, do: op.opts, else: op.changes

    if Keyword.has_key?(stated, :type) or Keyword.has_key?(stated, :default) do
      {_name, type, opts} =
        member = List.keyfind!(next_model.entities[op.entity].attributes, op.name, 0)

      default = opts[:default]

      reason =
        default != nil && default_refusal(default, member, op, bounds)

      if reason do
        raise Hologram.CompileError,
          message:
            "the default of #{inspect(op.name)} on #{inspect(op.entity)}#{line(op)} holds " <>
              "#{printed(default)}, which #{describe_refusal(default, type, reason)} - state a " <>
              "default: that fits in this op, or default: nil"
      end
    end

    :ok
  end

  defp validate_default!(_op, _next_model, _bounds), do: :ok

  defp validate_present!(nil, op) do
    refuse!(op, "is nil - a backfill is the value rows receive, so it needs one")
  end

  defp validate_present!(_backfill, _op), do: :ok

  # A computed fill's values are checked against the rules once it has run, so the rules have to
  # be ones the validator can run.
  defp validate_rules_fit!({_name, type, opts}, op) do
    case unfit_rule(type, opts) do
      nil -> :ok
      rule -> refuse_unfit_rule!(op, rule, type)
    end
  end

  defp validate_tightening!(%{op: kind, changes: changes} = op, model, next_model)
       when kind in [:change_attribute, :change_relationship] do
    # An op can state the type the member has.
    if Keyword.has_key?(changes, :type) and member_type(op, model) != member_type(op, next_model) do
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

  defp validate_value!(%Value{} = value, kind, member, op, model, _bounds) do
    if kind == :attribute, do: validate_rules_fit!(member, op)

    Value.resolve!(value, model, op.entity, Value.fill_target(kind, member, op))

    :ok
  end

  defp validate_value!(
         value,
         :relationship,
         {_name, target, _opts},
         op,
         _model,
         _bounds
       ) do
    normalized = Value.normalize_constant(value, :uuid)

    if not Validator.attribute_value_valid?(normalized, :uuid) do
      refuse!(op, "holds #{printed(value)}, which isn't the id of a #{inspect(target)}")
    end

    :ok
  end

  defp validate_value!(value, :attribute, member, op, _model, bounds) do
    {_name, type, _opts} = member

    case constant_refusal(value, member, op, bounds) do
      nil ->
        :ok

      {:unfit_rule, rule} ->
        refuse_unfit_rule!(op, rule, type)

      reason ->
        refuse!(op, "holds #{printed(value)}, which #{describe_refusal(value, type, reason)}")
    end
  end

  defp walk([], _model, _keys, _final_model), do: :ok

  defp walk([op | later_ops], model, keys, final_model) do
    bounds = op_bounds(op, later_ops, model, keys, final_model)

    validate!(op, model, bounds.next_model, bounds)

    walk(later_ops, bounds.next_model, bounds.keys, final_model)
  end

  defp widen(value, :float), do: Value.normalize_constant(value, :float)

  defp widen(value, _type), do: value
end
