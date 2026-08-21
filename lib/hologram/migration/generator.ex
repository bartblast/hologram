defmodule Hologram.Migration.Generator do
  @moduledoc false

  alias Hologram.Entity.Model
  alias Hologram.Migration
  alias Hologram.Migration.Diff
  alias Hologram.Migration.Loader
  alias Hologram.Migration.ShadowVerifier

  @indent "  "

  # The menu's calls are padded to one column so the outcomes line up, and the entity
  # module name makes the longest call variable.
  @menu_call_width 38

  # Entity-level ops are flat statements even though they name an entity - blocks scope
  # member ops, and these scope nothing. The designation names an entity type without
  # belonging to it, so a block would file it under the type it points at, or under nil
  # when the designation is being removed.
  @flat_entity_ops [:delete_entity, :designate_user_entity, :rename_entity]

  @doc """
  Writes the migration file taking the given directory's history to the given model,
  and returns what happened: :nothing_to_do when the history already produces the model,
  {:ok, path, question_count} when a file was written, or {:error, {:unresolved, entries}}
  when a draft is still waiting for its answers.

  An unresolved draft blocks generation - its questions are answered while the change is
  fresh, never stacked behind newer diffs that might change their meaning. The file is
  named after the given timestamp, bumped by a second while that name is taken.

  A resolve!-free outcome is a finalized history, and finalization is passing shadow
  verification - the full chain, a freshly written file included, is applied to a
  scratch database and must produce the model's schema, raising otherwise. A draft
  still holding questions is not verified: its marker ops carry no physical form yet.
  """
  @spec generate(String.t(), %{atom => any}, DateTime.t()) ::
          :nothing_to_do | {:ok, String.t(), non_neg_integer} | {:error, {:unresolved, list}}
  def generate(dir, current_model, timestamp) do
    migrations = Loader.load_dir!(dir)

    unresolved =
      Enum.flat_map(migrations, fn migration ->
        Enum.map(Loader.unresolved(migration.ops), &{migration.path, &1})
      end)

    if unresolved == [] do
      dir
      |> generate_file(migrations, current_model, timestamp)
      |> verify_finalized(dir, current_model)
    else
      {:error, {:unresolved, unresolved}}
    end
  end

  @doc """
  Returns the text of the migration file expressing the given plan.

  Entity renames come first, so every later line names the entity as the current model
  does - then the entity blocks in alphabetical order, then the flat ops. The rendered
  text is formatter-stable: the vocabulary is exported as parens-free, so a project's
  mix format leaves generated files alone.
  """
  @spec render(%{atom => any}) :: String.t()
  def render(plan) do
    sections =
      plan
      |> group_sections()
      |> Enum.map(&render_section/1)

    body = Enum.join(sections, "\n\n")
    text = "use Hologram.Migration\n\n" <> body <> "\n"

    format(text)
  end

  # The ops that can express each ambiguity, with what each one does to existing data.
  #
  # TODO: move_attribute belongs in the attribute menu, and in the relationship one if it
  # grows a counterpart - it is reserved vocabulary with no implementation yet, so naming
  # it here would point at an op the loader rejects. Adding it waits on the lens payload
  # that says where the value travels and what happens when several rows converge on one.
  defp api_entries(:attributes) do
    [
      "rename_attribute :old, :new             - the column is renamed, its data kept",
      "delete_attribute :name                  - the column and its data are dropped",
      "add_attribute :name, :type, opts        - a new column, empty for existing rows"
    ]
  end

  defp api_entries(:entities) do
    [
      "rename_entity MyApp.Old, MyApp.New      - the table is renamed, its rows kept",
      "delete_entity MyApp.Old                 - the table and its rows are dropped",
      "create_entity MyApp.New do ... end      - a new table"
    ]
  end

  defp api_entries(:enum_values) do
    [
      "rename_enum_value :attr, :old, :new     - the rows holding it follow the label",
      "delete_enum_value :attr, :value         - refused while rows still hold it",
      "add_enum_value :attr, :value, opts      - before:/after: place it in the order"
    ]
  end

  defp api_entries(:relationships) do
    [
      "rename_relationship :old, :new          - the reference is renamed, its data kept",
      "delete_relationship :name               - the reference and its data are dropped",
      "add_relationship :name, Target, opts    - a new reference, empty for existing rows"
    ]
  end

  defp api_entries(:roles) do
    [
      "rename_role :old, :new                  - existing grants follow the label",
      "delete_role :name                       - the grants of that role die with it",
      "add_role :name, opts                    - a new grantable role"
    ]
  end

  # The store's fate differs by direction: a move rebuilds its references against the new
  # type, a removal takes the store with it. Both delete every grant first, which is what
  # the question exists to have a human confirm.
  defp designation_entries(question) do
    outcome =
      if question.to == nil,
        do: "the role grant store is dropped",
        else: "the store's references follow it"

    entries = [
      {"delete_role_grants()", "every grant in the store is deleted"},
      {"designate_user_entity #{inspect(question.to)}", outcome}
    ]

    Enum.map(entries, fn {call, description} ->
      "#{String.pad_trailing(call, @menu_call_width)} - #{description}"
    end)
  end

  defp designation_summary(%{to: nil}), do: "the user entity designation is being removed"

  defp designation_summary(question) do
    "the user entity designation is moving from #{inspect(question.from)} to " <>
      "#{inspect(question.to)}"
  end

  defp block_op?(op) do
    Map.has_key?(op, :entity) and op.op not in @flat_entity_ops
  end

  defp entity_of(op), do: Map.get(op, :entity)

  # Generated text is formatted text: a long payload wraps here rather than the first
  # time someone runs mix format, so a fresh file is never a pending diff.
  # Written out per attribute with its own name and type, so the answer is an edit of a
  # line rather than a recall of the option's spelling.
  defp fill_entries(members) do
    Enum.flat_map(members, fn {name, type, opts} ->
      declared_opts = render_opts(opts)
      suffix = if declared_opts == "", do: "", else: ", " <> declared_opts
      call = "add_attribute #{inspect(name)}, #{inspect(type)}#{suffix}"

      [
        "#{call}, backfill: <value>  - existing rows receive it, once",
        "#{call}, default: <value>   - every row created without one, from now on",
        "#{call}, optional: true     - existing rows stay empty"
      ]
    end)
  end

  defp format(text) do
    formatted =
      Code.format_string!(text, locals_without_parens: Migration.locals_without_parens())

    IO.iodata_to_binary([formatted, "\n"])
  end

  defp generate_file(dir, migrations, current_model, timestamp) do
    replayed = Enum.reduce(migrations, Model.empty(), &Model.fold(&2, &1.ops))
    plan = Diff.diff(replayed, current_model)

    if plan.ops == [] and plan.questions == [] do
      :nothing_to_do
    else
      path = Path.join(dir, "#{next_version(dir, timestamp)}.exs")

      File.mkdir_p!(dir)
      File.write!(path, render(plan))

      {:ok, path, length(plan.questions)}
    end
  end

  # Sections in canonical order: the questions demanding attention first, then the
  # renames (the ordering rule - every later line names the current model's spelling),
  # then the entity blocks, then the flat ops that take no scope.
  defp group_sections(plan) do
    {entity_ops, flat_ops} = Enum.split_with(plan.ops, &block_op?/1)
    {renames, other_flat_ops} = Enum.split_with(flat_ops, &(&1.op == :rename_entity))
    {block_questions, flat_questions} = Enum.split_with(plan.questions, &(entity_of(&1) != nil))

    ops_by_entity = Enum.group_by(entity_ops, &entity_of/1)
    questions_by_entity = Enum.group_by(block_questions, &entity_of/1)

    blocks =
      ops_by_entity
      |> Map.keys()
      |> Enum.concat(Map.keys(questions_by_entity))
      |> Enum.uniq()
      |> Enum.sort_by(&inspect/1)
      |> Enum.map(fn entity_type ->
        {:block, entity_type, Map.get(ops_by_entity, entity_type, []),
         Map.get(questions_by_entity, entity_type, [])}
      end)

    Enum.map(flat_questions, &{:question, &1}) ++
      Enum.map(renames, &{:flat, &1}) ++
      blocks ++ Enum.map(other_flat_ops, &{:flat, &1})
  end

  defp indent(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &"#{@indent}#{&1}")
  end

  defp name_list(names) do
    Enum.map_join(names, ", ", &inspect/1)
  end

  # Two generations within one second on one machine would mint the same name - the
  # version bumps until free, so the collision closes where names are minted rather
  # than by widening every file name.
  defp next_version(dir, timestamp) do
    version = Calendar.strftime(timestamp, "%Y%m%d%H%M%S")

    path = Path.join(dir, "#{version}.exs")

    if File.exists?(path) do
      next_version(dir, DateTime.add(timestamp, 1, :second))
    else
      version
    end
  end

  defp plural_verb([_one]), do: "is"

  defp plural_verb(_many), do: "are"

  defp render_args(args) do
    Enum.map_join(args, ", ", &inspect/1)
  end

  defp render_hint({:rename, old, new}, %{kind: :enum_values} = question) do
    "rename_enum_value #{inspect(question.attribute)}, #{inspect(old)}, #{inspect(new)}"
  end

  defp render_hint({:rename, old, new}, question) do
    "#{rename_verb(question.kind)} #{inspect(old)}, #{inspect(new)}"
  end

  # An op renders as its verb followed by its arguments, keyword payloads spelled bare -
  # the same statement style the vocabulary macros accept.
  defp render_call(verb, args, opts) do
    rendered_opts = render_opts(opts)
    rendered_args = render_args(args)

    case {rendered_args, rendered_opts} do
      {"", ""} -> "#{verb}"
      {"", _opts} -> "#{verb} #{rendered_opts}"
      {_args, ""} -> "#{verb} #{rendered_args}"
      _both -> "#{verb} #{rendered_args}, #{rendered_opts}"
    end
  end

  defp render_op(%{op: :add_attribute} = op) do
    render_call("add_attribute", [op.name, op.type], op.opts)
  end

  defp render_op(%{op: :add_enum_value} = op) do
    render_call("add_enum_value", [op.attribute, op.value], op.opts)
  end

  defp render_op(%{op: :add_relationship} = op) do
    render_call("add_relationship", [op.name, op.type], op.opts)
  end

  defp render_op(%{op: :add_role, entity: _entity} = op) do
    render_call("add_role", [op.name], op.opts)
  end

  defp render_op(%{op: :add_role, role: role} = op) do
    render_call("add_role", [role], op.opts)
  end

  defp render_op(%{op: :change_attribute} = op) do
    render_call("change_attribute", [op.name], op.changes)
  end

  defp render_op(%{op: :change_relationship} = op) do
    render_call("change_relationship", [op.name], op.changes)
  end

  defp render_op(%{op: :change_role, entity: _entity} = op) do
    render_call("change_role", [op.name], op.changes)
  end

  defp render_op(%{op: :change_role, role: role} = op) do
    render_call("change_role", [role], op.changes)
  end

  defp render_op(%{op: :create_entity} = op) do
    render_call("create_entity", [op.entity], [])
  end

  defp render_op(%{op: :delete_attribute} = op) do
    render_call("delete_attribute", [op.name], [])
  end

  defp render_op(%{op: :delete_entity} = op) do
    render_call("delete_entity", [op.entity], [])
  end

  defp render_op(%{op: :delete_enum_value} = op) do
    render_call("delete_enum_value", [op.attribute, op.value], [])
  end

  defp render_op(%{op: :delete_relationship} = op) do
    render_call("delete_relationship", [op.name], [])
  end

  defp render_op(%{op: :delete_role, entity: _entity} = op) do
    render_call("delete_role", [op.name], [])
  end

  defp render_op(%{op: :delete_role, role: role}) do
    render_call("delete_role", [role], [])
  end

  # The one op with parens: a zero-arity call written bare parses as a variable rather
  # than a call, so the vocabulary's parens-free style cannot reach it.
  defp render_op(%{op: :delete_role_grants}), do: "delete_role_grants()"

  defp render_op(%{op: :designate_user_entity} = op) do
    render_call("designate_user_entity", [op.entity], [])
  end

  defp render_op(%{op: :rename_attribute} = op) do
    render_call("rename_attribute", [op.from, op.to], [])
  end

  defp render_op(%{op: :rename_entity} = op) do
    render_call("rename_entity", [op.from, op.to], [])
  end

  defp render_op(%{op: :rename_enum_value} = op) do
    render_call("rename_enum_value", [op.attribute, op.from, op.to], [])
  end

  defp render_op(%{op: :rename_relationship} = op) do
    render_call("rename_relationship", [op.from, op.to], [])
  end

  defp render_op(%{op: :rename_role} = op) do
    render_call("rename_role", [op.from, op.to], [])
  end

  # The one op that reads as a refactor and is not one: the declared order of an enum is what
  # ordering by that attribute follows, so a tidied list changes what existing queries return.
  # The reassurance rides with the warning because the rebuild sounds worse than it is - the
  # cast round-trips every label through text, so no row can change or fail it.
  defp render_op(%{op: :reorder_enum_values} = op) do
    call = render_call("reorder_enum_values", [op.attribute, op.values], [])

    Enum.join(
      [
        "# The declared order of #{inspect(op.attribute)} changed - queries ordering by it sort rows differently now.",
        "# No value changes: every row keeps what it holds, and the column is rebuilt to apply the order.",
        call
      ],
      "\n"
    )
  end

  defp render_opts([]), do: ""

  defp render_opts(opts) do
    Enum.map_join(opts, ", ", fn {key, value} -> "#{key}: #{render_opt_value(value)}" end)
  end

  # The model keeps a regex as its pattern and flags rather than as a compiled struct, so that
  # two reads of one declaration compare equal - the migration file spells it the way the entity
  # type does. Building the regex back is what turns the flags into the modifiers they were
  # written as.
  defp render_opt_value({:regex, source, regex_opts}) do
    source
    |> Regex.compile!(regex_opts)
    |> inspect()
  end

  defp render_opt_value(value) do
    inspect(value)
  end

  # The draft form: the detected facts, the op API that expresses them, what looks
  # likely - and the resolve! line the human deletes once the ops are written. No
  # resolution is ever emitted as code: the lazy path must not be the destructive one.
  defp render_question(%{kind: :fill} = question) do
    fact_lines = [
      "RESOLVE: #{name_list(question.attributes)} #{plural_verb(question.attributes)} required, " <>
        "and #{inspect(question.entity)} already holds rows - they need a value.",
      "Write the op with one of these, then delete the resolve! line. API:"
    ]

    api_lines =
      question.members
      |> fill_entries()
      |> Enum.map(&"  #{&1}")

    render_comment_block(fact_lines ++ api_lines, question)
  end

  defp render_question(%{kind: :user_entity} = question) do
    fact_lines = [
      "RESOLVE: #{designation_summary(question)} - role grants reference " <>
        "#{inspect(question.from)} rows, so they cannot follow it.",
      "Write both ops, then delete the resolve! line. API:"
    ]

    api_lines =
      question
      |> designation_entries()
      |> Enum.map(&"  #{&1}")

    render_comment_block(fact_lines ++ api_lines, question)
  end

  defp render_question(question) do
    fact_lines = [
      "RESOLVE: #{name_list(question.deleted)} disappeared from #{subject(question)} - " <>
        "#{name_list(question.added)} appeared.",
      "Write the ops that express what happened, then delete the resolve! line. API:"
    ]

    api_lines =
      question.kind
      |> api_entries()
      |> Enum.map(&"  #{&1}")

    hint_lines = Enum.map(question.hints, &"Looks likely: #{render_hint(&1, question)}")

    render_comment_block(fact_lines ++ api_lines ++ hint_lines, question)
  end

  defp render_comment_block(lines, question) do
    lines
    |> Enum.map(&"# #{&1}")
    |> Enum.concat([render_resolve_op(question)])
    |> Enum.join("\n")
  end

  defp render_resolve_op(%{kind: :fill} = question) do
    render_call("resolve!", [question.kind], attributes: question.attributes)
  end

  defp render_resolve_op(%{kind: :user_entity} = question) do
    render_call("resolve!", [question.kind], from: question.from, to: question.to)
  end

  defp render_resolve_op(question) do
    payload =
      case question do
        %{attribute: attribute} -> [attribute: attribute]
        _other -> []
      end

    render_call(
      "resolve!",
      [question.kind],
      payload ++ [deleted: question.deleted, added: question.added]
    )
  end

  # An entity block whose ops include the creation renders as create_entity - the
  # creation itself is the header, never a member line. Questions come first inside the
  # block, so what needs a human is what a reader meets.
  defp render_section({:block, entity_type, ops, questions}) do
    {creations, member_ops} = Enum.split_with(ops, &(&1.op == :create_entity))
    verb = if creations == [], do: "change_entity", else: "create_entity"

    question_lines = Enum.map(questions, &indent(render_question(&1)))
    op_lines = Enum.map(member_ops, &"#{@indent}#{render_op(&1)}")
    body = Enum.join(question_lines ++ op_lines, "\n")

    "#{verb} #{inspect(entity_type)} do\n#{body}\nend"
  end

  defp render_section({:flat, op}), do: render_op(op)

  defp render_section({:question, question}), do: render_question(question)

  defp rename_verb(:attributes), do: "rename_attribute"

  defp rename_verb(:entities), do: "rename_entity"

  defp rename_verb(:relationships), do: "rename_relationship"

  defp rename_verb(:roles), do: "rename_role"

  defp subject(%{kind: :attributes}), do: "the attributes"

  defp subject(%{kind: :entities}), do: "the entity types"

  defp subject(%{kind: :enum_values} = question) do
    "the values of #{inspect(question.attribute)}"
  end

  defp subject(%{kind: :relationships}), do: "the relationships"

  defp subject(%{kind: :roles}), do: "the roles"

  defp verify_finalized(:nothing_to_do, dir, current_model) do
    migrations = Loader.load_dir!(dir)
    ShadowVerifier.verify!(migrations, current_model)

    :nothing_to_do
  end

  defp verify_finalized({:ok, path, 0} = outcome, dir, current_model) do
    try do
      migrations = Loader.load_dir!(dir)

      ShadowVerifier.verify!(migrations, current_model)
    rescue
      error ->
        # A file that cannot be read back, or cannot build the model, is not history - left
        # on disk it becomes the history of the next run, which then replays the rejected
        # ops and reports the same failure forever, with nothing to say the file is the
        # cause. The load reads the file just written, so it fails the same way.
        File.rm(path)

        reraise error, __STACKTRACE__
    end

    outcome
  end

  defp verify_finalized(outcome, _dir, _current_model), do: outcome
end
