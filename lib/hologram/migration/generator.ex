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
  Writes the migration module taking the given migration history to the given model, and
  returns what happened: :nothing_to_do when the history already produces the model,
  {:ok, path, question_count} when a file was written, or {:error, {:unresolved, entries}}
  when a draft is still waiting for its answers.

  Options:
    * `:dir` - the directory the file is written to (required)
    * `:namespace` - the namespace of the module, unless a migration in `:dir` already has
      one - the newest of those is followed, so a project that renamed it keeps the new one.
      Required while `:dir` holds no migration
    * `:format` - formats the module text, by default with the vocabulary's
      locals_without_parens alone; the generate task passes the project's formatter

  An unresolved draft blocks generation - its questions are answered while the change is
  fresh, never stacked behind newer diffs that might change their meaning. The file is
  named after the given timestamp, bumped by a second while that version is taken.

  A resolve!-free file is compiled at once, so one the build would refuse never stays
  behind, and finalization is passing shadow verification - the full chain, the fresh
  migration included, is applied to a scratch database and must produce the model's schema,
  raising otherwise. A file that fails to compile or to verify is removed and its module
  unloaded. A draft still holding questions is neither compiled nor verified: its marker ops
  carry no physical form yet, and the developer edits it next.
  """
  @spec generate(list(%{atom => any}), %{atom => any}, DateTime.t(), keyword) ::
          :nothing_to_do | {:ok, String.t(), non_neg_integer} | {:error, {:unresolved, list}}
  def generate(migrations, current_model, timestamp, opts) do
    unresolved = Loader.unresolved_entries(migrations)

    if unresolved == [] do
      migrations
      |> generate_file(current_model, timestamp, opts)
      |> verify_finalized(migrations, current_model)
    else
      {:error, {:unresolved, unresolved}}
    end
  end

  @doc """
  Returns the text of the migration module with the given name expressing the given plan,
  formatted with the given function.

  Entity renames come first, so every later line names the entity as the current model
  does - then the blocks creating entity types, so a relationship never sits above the type it
  targets, then the other entity blocks, each group in alphabetical order, then the flat ops. The default
  formatting writes the vocabulary parens-free, as a project importing Hologram's formatter
  config formats it; the generate task formats with the project's own config, so a fresh
  file is what the project's mix format would write.
  """
  @spec render(%{atom => any}, module, (String.t() -> String.t())) :: String.t()
  def render(plan, module, format \\ &format/1) do
    sections =
      plan
      |> group_sections()
      |> Enum.map(&render_section/1)

    body = Enum.join(sections, "\n\n")

    # @moduledoc false because Credo's strict checks read the source, where the module
    # the generator writes would otherwise have none.
    format.("""
    defmodule #{inspect(module)} do
    @moduledoc false

    use Hologram.Migration

    #{body}
    end
    """)
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

  defp backfill_lines(call, value, rows) do
    [
      "#{call}, backfill: #{value}  - #{rows} receive it, once, computed from each row when " <>
        "it names the row's fields",
      "#{call}, backfill: fn field -> <query words> end  - the same, in one update",
      "#{call}, backfill: fn field -> <Elixir> end  - the same, run row by row"
    ]
  end

  defp block_op?(op) do
    Map.has_key?(op, :entity) and op.op not in @flat_entity_ops
  end

  defp asks_fill?(questions), do: Enum.any?(questions, &(&1.kind == :fill))

  defp created?(ops), do: Enum.any?(ops, &(&1.op == :create_entity))

  defp entity_of(op), do: Map.get(op, :entity)

  # Generated text is formatted text: a long payload wraps here rather than the first
  # time someone runs mix format, so a fresh file is never a pending diff.
  # Written out per attribute with its own name and type, so the answer is an edit of a
  # line rather than a recall of the option's spelling.
  defp fill_entries(members) do
    Enum.flat_map(members, fn
      {kind, name, changes} ->
        tightening_lines(kind, name, changes)

      {kind, name, type, opts} ->
        declared_opts = render_opts(opts)
        suffix = if declared_opts == "", do: "", else: ", " <> declared_opts

        fill_lines(kind, "#{kind} #{inspect(name)}, #{inspect(type)}#{suffix}", opts)
    end)
  end

  # A to-one takes no default, since a default id would point every new row at one target.
  defp fill_lines(:add_relationship, call, _opts) do
    call
    |> backfill_lines("<id or expression>", "existing rows")
    |> Enum.concat(["#{call}, optional: true  - existing rows stay empty"])
  end

  # Nor does a unique attribute, since a default is one value for every row that omits it.
  defp fill_lines(_kind, call, opts) do
    default_lines =
      if opts[:unique] == true,
        do: [],
        else: ["#{call}, default: <value>  - every row created without one, from now on"]

    call
    |> backfill_lines("<value or expression>", "existing rows")
    |> Enum.concat(default_lines)
    |> Enum.concat(["#{call}, optional: true  - existing rows stay empty"])
  end

  defp format(text) do
    formatted =
      Code.format_string!(text, locals_without_parens: Migration.locals_without_parens())

    IO.iodata_to_binary([formatted, "\n"])
  end

  # A module that compiled but failed verification is unloaded with its file, so a retry in
  # the same VM compiles it afresh. One that failed to compile was never left loaded, and the
  # unload is then a no-op.
  defp discard_file(path, module) do
    File.rm(path)
    :code.delete(module)
    :code.purge(module)
  end

  defp generate_file(migrations, current_model, timestamp, opts) do
    replayed = Enum.reduce(migrations, Model.empty(), &Model.fold(&2, &1.ops))
    plan = Diff.diff(replayed, current_model)

    if plan.ops == [] and plan.questions == [] do
      :nothing_to_do
    else
      dir = Keyword.fetch!(opts, :dir)
      format = Keyword.get(opts, :format, &format/1)

      version = next_version(dir, timestamp, migrations)
      module = module_name(migrations, version, opts)
      path = Path.join(dir, "#{version}.ex")

      File.mkdir_p!(dir)
      File.write!(path, render(plan, module, format))

      question_count = length(plan.questions)

      # A draft is left uncompiled: it is not verified, and a build outside dev and test
      # refuses it by design, which would read as the file being broken.
      migration = if question_count == 0, do: load_written!(path, module)

      {:ok, path, question_count, migration}
    end
  end

  # Sections in canonical order: the questions demanding attention first, then the
  # renames (the ordering rule - every later line names the current model's spelling),
  # then the entity blocks, then the flat ops that take no scope. A backfill answering a fill
  # applies apart from the ops around it, so the ops above it have to stand without the ones
  # below: the blocks asking for a fill come after the others, and the members they make optional
  # go to blocks of their own above all of them, since another block's fill can need one ending
  # a cycle of required to-ones.
  defp group_sections(plan) do
    {entity_ops, flat_ops} = Enum.split_with(plan.ops, &block_op?/1)
    {renames, other_flat_ops} = Enum.split_with(flat_ops, &(&1.op == :rename_entity))
    {block_questions, flat_questions} = Enum.split_with(plan.questions, &(entity_of(&1) != nil))

    ops_by_entity = Enum.group_by(entity_ops, &entity_of/1)
    questions_by_entity = Enum.group_by(block_questions, &entity_of/1)

    {fill_blocks, other_blocks} =
      ops_by_entity
      |> Map.keys()
      |> Enum.concat(Map.keys(questions_by_entity))
      |> Enum.uniq()
      |> Enum.sort_by(&{not created?(Map.get(ops_by_entity, &1, [])), inspect(&1)})
      |> Enum.map(fn entity_type ->
        {:block, entity_type, Map.get(ops_by_entity, entity_type, []),
         Map.get(questions_by_entity, entity_type, [])}
      end)
      |> Enum.split_with(fn {:block, _entity_type, _ops, questions} -> asks_fill?(questions) end)

    {relaxation_blocks, answered_blocks} =
      fill_blocks
      |> Enum.map(fn {:block, entity_type, ops, questions} ->
        {relaxations, later_ops} = Enum.split_with(ops, &relaxation?/1)

        {{:block, entity_type, relaxations, []}, {:block, entity_type, later_ops, questions}}
      end)
      |> Enum.unzip()

    Enum.map(flat_questions, &{:question, &1}) ++
      Enum.map(renames, &{:flat, &1}) ++
      other_blocks ++
      Enum.reject(relaxation_blocks, &match?({:block, _entity_type, [], _questions}, &1)) ++
      answered_blocks ++ Enum.map(other_flat_ops, &{:flat, &1})
  end

  defp indent(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &"#{@indent}#{&1}")
  end

  # What's left of the change once the member stays optional, which still has to be written.
  defp keep_optional_line(_kind, name, []) do
    "keep optional: true on #{inspect(name)} in the entity type  - no op, the nils stay"
  end

  defp keep_optional_line(kind, name, other_changes) do
    "#{render_call(Atom.to_string(kind), [name], other_changes)}  - keep optional: true on " <>
      "#{inspect(name)} in the entity type, the nils stay"
  end

  # A key naming a member the question asks about is withheld with it, and the two answers
  # treat it differently - said here, because the replay refuses a delete without its line,
  # and refuses the ops below when a renamed key still names what they take away.
  defp key_lines(question, ops) do
    delete_lines =
      for %{op: :delete_unique, fields: fields} <- question.withheld_ops do
        key = inspect(fields)

        "Key #{key} names what disappeared - a rename carries it along, " <>
          "a delete needs delete_unique #{key} first#{taken_fields_note(fields, ops)}"
      end

    add_lines =
      for %{op: :add_unique, fields: fields} <- question.withheld_ops do
        "Key #{inspect(fields)} names what appeared - the next generated file adds it " <>
          "if the answer leaves it out"
      end

    delete_lines ++ add_lines
  end

  defp name_list(names) do
    Enum.map_join(names, ", ", &inspect/1)
  end

  # The file compiled is the one this run just wrote into the app's own migrations directory -
  # the same code the next mix compile builds.
  # sobelow_skip ["RCE.Compile"]
  defp load_written!(path, module) do
    Code.compile_file(path)

    [migration] = Loader.from_modules!([module])

    migration
  rescue
    error ->
      discard_file(path, module)

      reraise error, __STACKTRACE__
  end

  # The module name is new by construction - it holds the version just minted - and is made
  # once per generated file, by a developer's task run, never from a request.
  # sobelow_skip ["DOS.ModuleConcat"]
  defp module_name(migrations, version, opts) do
    migrations
    |> namespace(opts)
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    |> Module.concat("V#{version}")
  end

  # The history spans every app reaching Hologram - an umbrella sibling's or a dependency's
  # migrations among them - so only the migrations in the target directory say which
  # namespace this app's migrations use. The namespace is an existing module's, minus its
  # last segment.
  # sobelow_skip ["DOS.ModuleConcat"]
  defp namespace(migrations, opts) do
    dir =
      opts
      |> Keyword.fetch!(:dir)
      |> Path.expand()

    newest_here =
      migrations
      |> Enum.filter(&(source_dir(&1.module) == dir))
      |> List.last()

    if newest_here do
      segments =
        newest_here.module
        |> Module.split()
        |> Enum.drop(-1)

      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      Module.concat(segments)
    else
      Keyword.fetch!(opts, :namespace)
    end
  end

  # Two generations within one second on one machine would mint the same version - it
  # bumps until free, so the collision closes where versions are minted rather than by
  # widening every file name.
  defp next_version(dir, timestamp, migrations) do
    version = Calendar.strftime(timestamp, "%Y%m%d%H%M%S")

    taken? =
      Enum.any?(migrations, &(&1.version == version)) or
        dir
        |> Path.join("#{version}.ex")
        |> File.exists?()

    if taken? do
      next_version(dir, DateTime.add(timestamp, 1, :second), migrations)
    else
      version
    end
  end

  defp plural_verb([_one]), do: "is"

  defp plural_verb(_many), do: "are"

  defp relaxation?(%{op: kind, changes: [optional: true]})
       when kind in [:change_attribute, :change_relationship],
       do: true

  defp relaxation?(_op), do: false

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

  defp render_op(%{op: :add_unique} = op) do
    render_call("add_unique", [op.fields], [])
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

  defp render_op(%{op: :delete_unique} = op) do
    render_call("delete_unique", [op.fields], [])
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
  # sobelow_skip ["DOS.Regex"]
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
  defp render_question(%{kind: :fill} = question, _ops) do
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

  defp render_question(%{kind: :user_entity} = question, _ops) do
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

  defp render_question(question, ops) do
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

    render_comment_block(
      fact_lines ++ api_lines ++ hint_lines ++ key_lines(question, ops),
      question
    )
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
  # block, so what needs a human is what a reader meets - after the keys that leave, though:
  # an answer is written where its question sits, and one that brings a member under a name
  # a leaving key still holds would be refused with the key's delete two lines below it.
  defp render_section({:block, entity_type, ops, questions}) do
    {creations, member_ops} = Enum.split_with(ops, &(&1.op == :create_entity))
    {key_deletes, later_ops} = Enum.split_with(member_ops, &(&1.op == :delete_unique))
    verb = if creations == [], do: "change_entity", else: "create_entity"

    key_delete_lines = Enum.map(key_deletes, &"#{@indent}#{render_op(&1)}")
    question_lines = Enum.map(questions, &indent(render_question(&1, later_ops)))
    op_lines = Enum.map(later_ops, &"#{@indent}#{render_op(&1)}")
    body = Enum.join(key_delete_lines ++ question_lines ++ op_lines, "\n")

    "#{verb} #{inspect(entity_type)} do\n#{body}\nend"
  end

  defp render_section({:flat, op}), do: render_op(op)

  defp render_section({:question, question}), do: render_question(question, [])

  defp rename_verb(:attributes), do: "rename_attribute"

  defp rename_verb(:entities), do: "rename_entity"

  defp rename_verb(:relationships), do: "rename_relationship"

  defp rename_verb(:roles), do: "rename_role"

  # A beam stripped of its compile info names no source, and no directory holds it.
  defp source_dir(module) do
    source =
      :compile
      |> module.module_info()
      |> Keyword.get(:source)

    if source do
      source
      |> to_string()
      |> Path.dirname()
    end
  end

  defp subject(%{kind: :attributes}), do: "the attributes"

  defp subject(%{kind: :entities}), do: "the entity types"

  defp subject(%{kind: :enum_values} = question) do
    "the values of #{inspect(question.attribute)}"
  end

  defp subject(%{kind: :relationships}), do: "the relationships"

  defp subject(%{kind: :roles}), do: "the roles"

  # The fields of a key that the ops written below the question delete, or turn into a
  # to-many: a rename keeps the key, respelled, and those ops then pull a field from under it.
  defp taken_fields_note(fields, ops) do
    taken =
      for %{name: name} = op <- ops, name in fields, takes_key_field?(op), uniq: true, do: name

    if taken == [] do
      ""
    else
      " - the ops below take #{name_list(taken)} from it, so a rename leaves the key " <>
        "needing a delete_unique of its own"
    end
  end

  defp takes_key_field?(%{op: op}) when op in [:delete_attribute, :delete_relationship], do: true

  defp takes_key_field?(%{op: :change_relationship, changes: changes}),
    do: is_list(Keyword.get(changes, :type))

  defp takes_key_field?(_op), do: false

  # A backfill can't sit beside a type change, since it would hold values of the new type while
  # the column has the old one, so that answer is two ops.
  defp tightening_lines(kind, name, changes) do
    value =
      if kind == :change_relationship, do: "<id or expression>", else: "<value or expression>"

    plain = render_call(Atom.to_string(kind), [name], changes)

    {type_lines, tightening} =
      if Keyword.has_key?(changes, :type) do
        first = render_call(Atom.to_string(kind), [name], Keyword.delete(changes, :optional))

        {["#{first}  - first, as an op of its own, when a backfill follows"],
         render_call(Atom.to_string(kind), [name], optional: false)}
      else
        {[], plain}
      end

    type_lines ++
      backfill_lines(tightening, value, "the rows holding nil") ++
      [
        "#{plain}  - every row already holds a value - the apply refuses otherwise",
        keep_optional_line(kind, name, Keyword.delete(changes, :optional))
      ]
  end

  defp verify_finalized(:nothing_to_do, migrations, current_model) do
    ShadowVerifier.verify!(migrations, current_model)

    :nothing_to_do
  end

  defp verify_finalized({:ok, path, 0, migration}, migrations, current_model) do
    # Replayed at its place in version order, as every later load replays it - a migration
    # already holding a later version sorts after it.
    history = Enum.sort_by([migration | migrations], & &1.version)

    try do
      ShadowVerifier.verify!(history, current_model)
    rescue
      error ->
        # A migration that cannot build the model is not history - left on disk it becomes
        # the history of the next run, which then replays the rejected ops and reports the
        # same failure forever, with nothing to say the file is the cause.
        discard_file(path, migration.module)

        reraise error, __STACKTRACE__
    end

    {:ok, path, 0}
  end

  defp verify_finalized({:ok, path, question_count, _migration}, _migrations, _current_model) do
    {:ok, path, question_count}
  end
end
