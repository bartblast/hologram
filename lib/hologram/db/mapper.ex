defmodule Hologram.DB.Mapper do
  @moduledoc false

  alias Hologram.Auth.RoleGrant
  alias Hologram.Commons.CryptographicUtils
  alias Hologram.DB.Codec
  alias Hologram.Entity.Model
  alias Hologram.Reflection

  # Bytes of the digest a shortened identifier carries - each spells as two hex characters.
  @digest_bytes 4

  # PostgreSQL truncates an enum label past 63 bytes silently, and a truncated label no longer
  # decodes to the value it was stored for.
  @max_enum_label_bytes 63

  # PostgreSQL truncates identifiers to 63 bytes - derived identifiers must never rely on that.
  @max_identifier_bytes 63

  # The two columns holding a row's place in the server's order. Taken from the oplog's sequence by
  # the statement writing the row, so an entity never supplies them.
  @sequence_columns ["server_created_seq", "server_updated_seq"]

  # The system columns every row carries beside its id.
  @stamp_columns [
    {"created_at", :datetime, "timestamptz"},
    {"server_created_at", :datetime, "timestamptz"},
    {"server_created_seq", :integer, "int8"},
    {"server_updated_at", :datetime, "timestamptz"},
    {"server_updated_seq", :integer, "int8"},
    {"updated_at", :datetime, "timestamptz"}
  ]

  @doc """
  Returns the column definitions derived from the given entity type module, in physical order:
  id, declared attributes sorted by name, to-one relationship references sorted by name,
  system timestamps, the framework's revisions column, sort-key companions, search-key companions.

  Each definition is a map with :name (column name string), :type (the logical attribute type,
  as consumed by the codec), :sql_type (the SQL type name - a derived per-attribute enum type
  name for :enum attributes), :collation (the pinned per-column collation name, nil for types
  that carry none), :enum_values (the declared enum values as strings in declaration order,
  nil for non-enum types), :default (the declared default value, or the framework's own for a
  column it derives whole, nil when none - creation semantics owned by the write path,
  never a DB DEFAULT), :null (true only for optional
  declarations), :references (the referenced table name for to-one relationship columns,
  nil otherwise), :fk_constraint (the derived `<table>_<column>_$fk` constraint name for
  reference columns, nil otherwise), and :source (:system, :revisions, or the declaration the
  column is derived from). To-many relationships derive no columns - they live in join tables.
  No column carries a plain index here: the indexes beyond the primary key and the unique ones
  are derived from what the server reads (see `Hologram.DB.IndexPlan`).

  Each :string attribute derives a nullable `<attribute>_$sort` companion column (source
  `{:sort_key, name}`) holding the attribute's derived sort key - the order both executors
  sort and compare the attribute by. It is a column like any other the mapping derives:
  migrations create, rename and drop it with its attribute.

  Each :string attribute also derives a nullable `<attribute>_$search` companion
  (source `{:search_key, name}`) holding the attribute's search key: the whole folded value when
  it is longer than the sort key keeps, nil otherwise. A loose search reads it, or the sort key
  when it is nil, so a short string's folded value is stored once.

  Every table also carries a framework-owned `$revisions` column (source :revisions, type
  :map, a jsonb object): for each settable column - the attributes and the to-one references -
  the revision of the write that last set it, a stamp the writer authored. Never a struct
  field: readers route it into the struct's `__meta__`.

  Raises Hologram.CompileError when two declarations derive the same column name (an attribute
  named x_id collides with a to-one relationship named x).
  """
  @spec columns(module) :: list(%{atom => any})
  def columns(entity_type) do
    entry = %{
      attributes: entity_type.__attributes__(),
      relationships: entity_type.__relationships__()
    }

    columns_from_entry(entity_type, entry)
  end

  @doc """
  Returns the name of the PostgreSQL schema the entity tables and join tables live in, unquoted.
  """
  @spec data_schema() :: String.t()
  def data_schema, do: "hologram_data"

  @doc """
  Derives the complete physical name mapping for the given entity type modules and global role
  modules.

  Runs every derivation check exactly once - table name collisions, required to-one cycles,
  per-entity column collisions, and cross-entity within-kind derived name collisions (join
  tables, enum types, and entity index names with the primary key constraints sharing
  their namespace, whose single-underscore seams can merge to the same name across
  entities) - and returns a map from entity type module to its mapping: :table (the table
  name), :pk_constraint (the derived `<table>_$pk` constraint name), :columns (as returned
  by columns/1), :indexes (index name to %{columns:, nulls_distinct:, unique:} - a
  `<table>_<attribute>_$uidx` entry per `unique: true` attribute, a `<table>_<column>_$uidx`
  entry per `unique: true` to-one over its reference column, a `<table>_<columns>_$uidx` entry
  per key declared with unique over its fields' columns in declared order, plus the role grant
  store's framework-owned one - the other indexes come from `Hologram.DB.IndexPlan`), and
  :join_tables (as returned by join_tables/1).
  """
  @spec derive!(list(module), list(module)) :: %{module => %{atom => any}}
  def derive!(entity_types, role_modules) do
    # The collision check is a pure function of the module atoms - running it before
    # reflection keeps its readable error ahead of any missing-module crash.
    validate_table_names!(entity_types)

    entity_types
    |> Model.from_modules(role_modules)
    |> derive_from_model!()
  end

  @doc """
  Derives the complete physical name mapping for the given model term.

  Same checks and result shape as derive!/2, plus the role grant store, whose entry is
  derived from the term rather than declared. The term form derives without consulting
  any module, so a mapping is obtainable for entity types that no longer exist as code
  (a replayed migration history names them as plain module atoms).
  """
  @spec derive_from_model!(%{atom => any}) :: %{module => %{atom => any}}
  def derive_from_model!(model) do
    entities = put_role_grant(model)

    entities
    |> Map.keys()
    |> validate_table_names!()

    validate_model_cycles!(entities)

    # The entity's own index entries carry the declaration each derives from, which the :indexes
    # map drops - the collision check names both sides, and a map would also merge away a
    # duplicate inside one entity before the check saw it.
    derived =
      Map.new(entities, fn {entity_type, entry} ->
        segments = table_segments(entity_type)
        index_entries = entity_index_entries(entity_type, entry, segments)

        entity_mapping = %{
          table: table_name(entity_type),
          pk_constraint: fit_identifier(segments, [], "$pk"),
          columns: columns_from_entry(entity_type, entry),
          indexes:
            Map.new(index_entries, fn {name, definition, _declaration} -> {name, definition} end),
          join_tables: join_tables_from_entry(entity_type, entry)
        }

        {entity_type, {entity_mapping, index_entries}}
      end)

    mapping =
      Map.new(derived, fn {entity_type, {entity_mapping, _entries}} ->
        {entity_type, entity_mapping}
      end)

    index_entries =
      Map.new(derived, fn {entity_type, {_entity_mapping, entries}} -> {entity_type, entries} end)

    validate_derived_names!(mapping, index_entries)

    mapping
  end

  @doc """
  Returns whether the given column definition is a companion derived from another column's
  value - a sort key or a search key - rather than a field an entity holds.
  """
  @spec derived?(%{atom => any}) :: boolean
  def derived?(%{source: {kind, _name}}) when kind in [:search_key, :sort_key], do: true

  def derived?(_column), do: false

  # The rule is part of every database Hologram manages. Indexes, join tables and enum types
  # follow a change to it through renames, but tables and columns don't: the reconciler can't
  # tell a renamed table or column from a dropped one plus a new one. So once the data layer is
  # released, the part of the rule that names tables and columns can't change without dev
  # rebuilding them and a migration-managed boot refusing.
  @doc """
  Returns the identifier built from the given parts, fitted to the PostgreSQL identifier limit.

  The parts are the owning table's segments (outermost first, the entity's own name last, none
  for a column name), whole column names in order, and the kind suffix (like "$fk", "id", or
  nil for a table name). Joined with single underscores, a name that fits is returned as is.

  One over the limit becomes `<kept>_<digest>_<kind>`: the digest is a short deterministic hash
  of the whole joined name, and the kept part comes from dropping, until it fits, the leading
  table segments while more than one remains, then the trailing columns while more than one
  remains, then the last table segment when a column remains, and at last cutting the one piece
  left at a character boundary. The kind always survives, so a name still says what it is, and
  what survives longest is the lead column, then the entity's own name.
  """
  @spec fit_identifier(list(String.t()), list(String.t()), String.t() | nil) :: String.t()
  def fit_identifier(table_segments, columns, kind) do
    identifier = join_identifier(table_segments ++ columns, kind)

    if byte_size(identifier) > @max_identifier_bytes do
      digest = CryptographicUtils.short_digest(identifier, @digest_bytes)
      tail = join_identifier([digest], kind)
      budget = @max_identifier_bytes - byte_size(tail) - 1

      case cut_parts(table_segments, columns, budget) do
        "" -> tail
        kept -> kept <> "_" <> tail
      end
    else
      identifier
    end
  end

  @doc """
  Returns the join table definitions derived from the given entity type module's to-many
  relationships, sorted by relationship name.

  Each definition is a map with :name (the join table name - `<source_table>_<relationship>_$join`
  per the derived-name system), :relationship (the declaring relationship name), :source_table,
  :target_table, :pk_constraint, :source_fk_constraint, and :target_fk_constraint (the derived constraint
  names). Join table columns are fixed: source_id/target_id uuid NOT NULL, composite primary
  key (source_id, target_id), both columns FK ON DELETE RESTRICT. To-one relationships derive
  no join tables - they live as reference columns on the owning row.
  """
  @spec join_tables(module) :: list(%{atom => any})
  def join_tables(entity_type) do
    join_tables_from_entry(entity_type, %{relationships: entity_type.__relationships__()})
  end

  @doc """
  Returns the given identifier wrapped in double quotes, with embedded double quotes escaped.
  Emitted SQL always quotes identifiers, so no derived name can ever clash with a reserved word.
  """
  @spec quote_identifier(String.t()) :: String.t()
  def quote_identifier(identifier) do
    ~s("#{String.replace(identifier, ~s("), ~s(""))}")
  end

  @doc """
  Returns the entity type and relationship whose reference the given foreign key constraint
  enforces - a to-one reference column's `<table>_<relationship>_id_$fk`, or a join table's
  `<join table>_target_id_$fk` - or nil when no relationship in the given mapping derives it.

  The source side of a join table is never asked for: a row's own outgoing edges are removed
  with it, so only the target side can refuse a delete.
  """
  @spec referencing_relationship(%{module => %{atom => any}}, String.t()) :: {module, atom} | nil
  def referencing_relationship(mapping, constraint) do
    Enum.find_value(mapping, fn {entity_type, entry} ->
      column_reference(entity_type, entry, constraint) ||
        edge_reference(entity_type, entry, constraint)
    end)
  end

  @doc """
  Returns whether the given column definition holds one of a row's two sequence numbers, which the
  statement writing the row takes from the oplog's sequence rather than from the entity.
  """
  @spec sequence?(%{atom => any}) :: boolean
  def sequence?(%{name: name}), do: name in @sequence_columns

  @doc """
  Returns the name of the PostgreSQL schema the framework's own bookkeeping tables live in - the
  managed-database marker, the migration history, the operations log, the mutation record and the
  schema object registry - unquoted.
  """
  @spec system_schema() :: String.t()
  def system_schema, do: "hologram_system"

  @doc """
  Returns the table name derived from the given entity type module.

  The name is the snake_cased module path with the leading segment stripped when it matches
  the primary OTP app's conventional root namespace - modules from other roots (guest apps,
  libraries) keep their full path. A name over the PostgreSQL identifier limit keeps the
  entity's own name, cut when it has to be, followed by a short deterministic hash of the full
  name (see fit_identifier/3).

  Framework-provided entity types are pinned to their full snake_cased path, so their
  tables carry the hologram_ prefix in every project - path derivation would strip it
  inside the framework's own repository, where the root namespace is Hologram.
  """
  @spec table_name(module) :: String.t()
  def table_name(entity_type) do
    entity_type
    |> table_segments()
    |> fit_identifier([], nil)
  end

  @doc """
  Returns the table segments of the given entity type module - its module path below the app's
  root, each part underscored - the parts every name derived for its table, its join tables and
  their objects is fitted from (see fit_identifier/3). A framework-provided entity type is pinned
  whole, as one segment, the way its table name is.
  """
  @spec table_segments(module) :: list(String.t())
  def table_segments(Hologram.Auth.RoleGrant), do: ["hologram_role_grant"]

  def table_segments(entity_type) do
    root =
      Reflection.otp_app()
      |> Atom.to_string()
      |> Macro.camelize()

    entity_type
    |> Module.split()
    |> strip_root(root)
    |> Enum.map(&Macro.underscore/1)
  end

  @doc """
  Validates that the given entity type modules form no cycles of required to-one
  relationships (self-references included).

  Returns :ok, or raises Hologram.CompileError listing the detected cycles. No row inside
  such a cycle can ever be created - every insert would require an already existing row
  further along the cycle - so at least one relationship in each cycle must be declared
  optional: true (a nullable reference column breaks the cycle). Optional to-one and
  to-many relationships never form cycle edges.
  """
  @spec validate_required_to_one_cycles!(list(module)) :: :ok
  def validate_required_to_one_cycles!(entity_types) do
    entity_types
    |> Model.from_modules()
    |> Map.fetch!(:entities)
    |> validate_model_cycles!()
  end

  @doc """
  Validates that no two of the given entity type modules derive the same table name.

  Returns :ok, or raises Hologram.CompileError listing every colliding table name together
  with all entity type modules that derive it. Collisions are possible because snake casing
  merges module boundaries (MyApp.Blog.Post and MyApp.BlogPost both derive "blog_post").
  """
  @spec validate_table_names!(list(module)) :: :ok
  def validate_table_names!(entity_types) do
    collisions =
      entity_types
      |> Enum.group_by(&table_name/1)
      |> Enum.filter(fn {_table_name, modules} -> length(modules) > 1 end)
      |> Enum.sort()

    if collisions != [] do
      descriptions =
        Enum.map_join(collisions, "\n", fn {table_name, modules} ->
          module_names =
            modules
            |> Enum.sort()
            |> Enum.map_join(", ", &inspect/1)

          "  * table name \"#{table_name}\" is derived from #{module_names}"
        end)

      raise Hologram.CompileError,
        message:
          "colliding table names - rename modules so that every entity type derives a unique table name:\n#{descriptions}"
    end

    :ok
  end

  # Rotates the cycle so that it starts at its smallest hop, giving every cycle a single
  # stable rendering regardless of which entity type the traversal entered it from.
  defp canonicalize_cycle(cycle) do
    start_index =
      cycle
      |> Enum.with_index()
      |> Enum.min_by(fn {{entity_type, name}, _index} -> {inspect(entity_type), name} end)
      |> elem(1)

    {hops_before_start, hops_from_start} = Enum.split(cycle, start_index)
    hops_from_start ++ hops_before_start
  end

  defp collation(:string), do: "C"

  defp collation(_type), do: nil

  defp column_reference(entity_type, entry, constraint) do
    case Enum.find(entry.columns, &(&1.fk_constraint == constraint)) do
      %{source: {:relationship, name}} -> {entity_type, name}
      nil -> nil
    end
  end

  defp columns_from_entry(entity_type, entry) do
    segments = table_segments(entity_type)

    attribute_columns =
      Enum.map(entry.attributes, fn {name, type, opts} ->
        %{
          name: Atom.to_string(name),
          type: type,
          sql_type: sql_type(type, segments, name),
          collation: collation(type),
          enum_values: enum_values(type, opts),
          default: Keyword.get(opts, :default),
          null: Keyword.get(opts, :optional) == true,
          references: nil,
          fk_constraint: nil,
          source: {:attribute, name}
        }
      end)

    to_one_columns =
      entry.relationships
      |> Enum.reject(fn {_name, type, _opts} -> is_list(type) end)
      |> Enum.map(fn {name, target, opts} ->
        column_name = reference_column_name(name)

        %{
          name: column_name,
          type: :id,
          sql_type: "uuid",
          collation: nil,
          enum_values: nil,
          default: nil,
          null: Keyword.get(opts, :optional) == true,
          references: table_name(target),
          fk_constraint: fit_identifier(segments, [column_name], "$fk"),
          source: {:relationship, name}
        }
      end)

    sort_columns = sort_key_columns(entry.attributes)
    search_columns = search_key_columns(entry.attributes)

    columns =
      [id_column() | attribute_columns] ++
        to_one_columns ++
        stamp_columns() ++ [revisions_column()] ++ sort_columns ++ search_columns

    validate_column_names!(entity_type, columns)

    columns
  end

  defp key_column(field, relationship_names) do
    if field in relationship_names,
      do: reference_column_name(field),
      else: Atom.to_string(field)
  end

  # One entry per key declared with unique, over its fields' columns in the order the declaration
  # names them - an attribute's own column, a to-one's reference column. Nulls stay distinct, as
  # for a unique attribute: a row holding nil in a field of the key repeats no other row. A to-one
  # leading a key needs no plain index of its own, since this one serves a lookup by the
  # reference, and the index plan counts it (see Hologram.DB.IndexPlan.select/2).
  defp key_entries(entity_type, entry, segments) do
    relationship_names = Enum.map(entry.relationships, fn {name, _type, _opts} -> name end)

    Enum.map(entry.uniques, fn fields ->
      columns = Enum.map(fields, &key_column(&1, relationship_names))

      {fit_identifier(segments, columns, "$uidx"),
       %{columns: columns, nulls_distinct: true, unique: true},
       "unique #{inspect(fields)} in #{inspect(entity_type)}"}
    end)
  end

  # One step at a time, re-measuring after each, so a name only loses what it has to.
  defp cut_parts(table_segments, columns, budget) do
    kept = Enum.join(table_segments ++ columns, "_")

    cond do
      byte_size(kept) <= budget ->
        kept

      match?([_first, _second | _rest], table_segments) ->
        cut_parts(tl(table_segments), columns, budget)

      match?([_first, _second | _rest], columns) ->
        cut_parts(table_segments, Enum.drop(columns, -1), budget)

      table_segments != [] and columns != [] ->
        cut_parts([], columns, budget)

      true ->
        cut_piece(kept, budget)
    end
  end

  # At a character boundary - PostgreSQL refuses an identifier holding a split character in a
  # UTF8 database. The underscores the cut leaves at the end go too, so the one the digest is
  # joined with never doubles.
  defp cut_piece(piece, budget) do
    piece
    |> String.codepoints()
    |> Enum.reduce_while("", fn codepoint, acc ->
      if byte_size(acc) + byte_size(codepoint) <= budget,
        do: {:cont, acc <> codepoint},
        else: {:halt, acc}
    end)
    |> String.trim_trailing("_")
  end

  defp describe_column_collision({name, group}) do
    sources = Enum.map_join(group, ", ", &describe_column_source/1)

    "  * column \"#{name}\" is derived from #{sources}"
  end

  # A column derived from a declaration names it. One the framework owns outright - the id, the
  # timestamps, the revisions - has no declaration to name, and saying so is the whole message for
  # a caller that collided with one: the declaration is theirs to rename, and the other side of the
  # collision is not.
  defp describe_column_source(%{source: {kind, declaration_name}}) do
    "#{kind} #{inspect(declaration_name)}"
  end

  defp describe_column_source(%{source: _framework}), do: "the framework"

  defp describe_cycle([{first_entity_type, _first_name} | _later_hops] = cycle) do
    hops =
      Enum.map_join(cycle, " -> ", fn {entity_type, name} ->
        "#{inspect(entity_type)} (relationship #{inspect(name)})"
      end)

    "  * #{hops} -> #{inspect(first_entity_type)}"
  end

  defp edge_reference(entity_type, entry, constraint) do
    case Enum.find(entry.join_tables, &(&1.target_fk_constraint == constraint)) do
      %{relationship: name} -> {entity_type, name}
      nil -> nil
    end
  end

  # Nulls stay distinct, so an optional unique attribute admits any number of rows holding
  # none: uniqueness is over the values an attribute holds, and nil is the absence of one.
  #
  # A unique to-one's reference column gets one too, under the same rule - an optional one admits
  # any number of rows referencing nothing. It serves every lookup by the reference, so the index
  # plan gives the column no plain index beside it (see Hologram.DB.IndexPlan.select/2).
  #
  # The index is over the raw column, so a string value is bounded by the btree entry limit -
  # the validator refuses a unique string above it, so the engine never gets to. The sort-key
  # companion sidesteps the same limit by indexing a bounded key, which a unique index cannot
  # do: a prefix is not unique.
  # TODO: a unique index over a hash expression lifts the bound for unbounded strings, once a
  # declaration needs it - it teaches the whole index chain an expression shape.
  defp entity_index_entries(entity_type, entry, segments) do
    attribute_entries =
      entry.attributes
      |> Enum.filter(fn {_name, _type, opts} -> Keyword.get(opts, :unique) == true end)
      |> Enum.map(fn {name, _type, _opts} ->
        column_name = Atom.to_string(name)

        {fit_identifier(segments, [column_name], "$uidx"),
         %{columns: [column_name], nulls_distinct: true, unique: true},
         "attribute #{inspect(name)} in #{inspect(entity_type)}"}
      end)

    reference_entries =
      entry.relationships
      |> Enum.filter(fn {_name, type, opts} ->
        not is_list(type) and Keyword.get(opts, :unique) == true
      end)
      |> Enum.map(fn {name, _type, _opts} ->
        column_name = reference_column_name(name)

        {fit_identifier(segments, [column_name], "$uidx"),
         %{columns: [column_name], nulls_distinct: true, unique: true},
         "relationship #{inspect(name)} in #{inspect(entity_type)}"}
      end)

    attribute_entries ++
      reference_entries ++
      key_entries(entity_type, entry, segments) ++ framework_index_entries(entity_type)
  end

  defp enum_values(:enum, opts) do
    opts
    |> Keyword.fetch!(:values)
    |> Enum.map(&Codec.encode(&1, :enum))
  end

  defp enum_values(_type, _opts), do: nil

  # Depth-first traversal over required to-one edges. The path holds the hops taken to reach
  # the current entity type (most recent first) - reaching an entity type already on the path
  # closes a cycle. Fully explored entity types are marked visited and never re-entered, so
  # each cycle is reported once.
  defp find_cycles(model, entity_type, path, cycles, visited) do
    if MapSet.member?(visited, entity_type) do
      {cycles, visited}
    else
      {cycles, visited} =
        model
        |> required_to_one_targets(entity_type)
        |> Enum.reduce({cycles, visited}, fn {name, target}, acc ->
          follow_edge(model, {entity_type, name}, target, path, acc)
        end)

      {cycles, MapSet.put(visited, entity_type)}
    end
  end

  # Closes a cycle when the target is already on the path, descends into the target otherwise.
  defp follow_edge(model, hop, target, path, {cycles, visited}) do
    new_path = [hop | path]

    if Enum.any?(new_path, fn {module, _name} -> module == target end) do
      {hops_beyond_target, [target_hop | _earlier_hops]} =
        Enum.split_while(new_path, fn {module, _name} -> module != target end)

      cycle = [target_hop | Enum.reverse(hops_beyond_target)]

      {[cycle | cycles], visited}
    else
      find_cycles(model, target, new_path, cycles, visited)
    end
  end

  # The role grant store carries a unique index no declaration derives, named like any other index
  # over several columns. Its reads that carry no user_id - who holds a role on a given entity -
  # get theirs from the index plan (see Hologram.DB.IndexPlan.framework_needs/1).
  #
  # The unique one is over the grant fact, with nulls compared as values - entity_type and
  # entity_id nils encode the type-wide and global grant shapes, so identical rows with nils must
  # still collide. Its columns are the store's own identity list, which its id derivation reads
  # too - one list, so the two cannot disagree on what a grant is. It leads with user_id, which
  # serves asking whether one user holds a role.
  defp framework_index_entries(Hologram.Auth.RoleGrant) do
    segments = table_segments(RoleGrant)

    [
      {fit_identifier(segments, RoleGrant.identity_columns(), "$uidx"),
       %{columns: RoleGrant.identity_columns(), nulls_distinct: false, unique: true},
       "the role grant store"}
    ]
  end

  defp framework_index_entries(_entity_type), do: []

  defp id_column do
    %{
      name: "id",
      type: :id,
      sql_type: "uuid",
      collation: nil,
      enum_values: nil,
      default: nil,
      null: false,
      references: nil,
      fk_constraint: nil,
      source: :system
    }
  end

  # Index names live in one namespace per schema, across tables, and a primary key is backed by
  # an index of its own name - so they are checked against each other. Foreign key names need no
  # check: PostgreSQL scopes them to their table, where they come from distinct column names. A
  # join table's primary key is listed too, since a cut can leave it in the same shape as an
  # entity's - it carries its join table's name, so a collision that only repeats one between the
  # join tables themselves is left to that report. The index plan's names end in a kind no name
  # here does, and it checks them among themselves (see Hologram.DB.IndexPlan.select/2).
  defp index_name_entries(entity_type, entity_mapping, entity_index_entries) do
    own_entries =
      Enum.map(entity_index_entries, fn {name, _definition, declaration} ->
        {name, declaration}
      end)

    pk_entry = {entity_mapping.pk_constraint, "the primary key of #{inspect(entity_type)}"}

    entity_entries =
      Enum.map([pk_entry | own_entries], fn {name, declaration} ->
        %{kind: "index", derived_name: name, declaration: declaration, join_table: nil}
      end)

    join_table_entries =
      Enum.map(entity_mapping.join_tables, fn join_table ->
        %{
          kind: "index",
          derived_name: join_table.pk_constraint,
          declaration:
            "relationship #{inspect(join_table.relationship)} in #{inspect(entity_type)}",
          join_table: join_table.name
        }
      end)

    entity_entries ++ join_table_entries
  end

  defp join_identifier(parts, nil), do: Enum.join(parts, "_")

  defp join_identifier([], kind), do: kind

  defp join_identifier(parts, kind), do: Enum.join(parts, "_") <> "_" <> kind

  # The join table's own objects take `<relationship>_$join` as their last table segment, so
  # a cut drops the source table's segments before it - and for a name that fits, the joined
  # string is the join table's name followed by the object's. Only a relationship name too long
  # to fit beside the object's column loses it, the way any table segment would.
  defp join_tables_from_entry(entity_type, entry) do
    source_segments = table_segments(entity_type)

    entry.relationships
    |> Enum.filter(fn {_name, type, _opts} -> is_list(type) end)
    |> Enum.map(fn {name, [target], _opts} ->
      relationship = Atom.to_string(name)
      join_segments = Enum.concat(source_segments, ["#{relationship}_$join"])

      %{
        name: fit_identifier(source_segments, [relationship], "$join"),
        relationship: name,
        source_table: table_name(entity_type),
        target_table: table_name(target),
        pk_constraint: fit_identifier(join_segments, [], "$pk"),
        source_fk_constraint: fit_identifier(join_segments, ["source_id"], "$fk"),
        target_fk_constraint: fit_identifier(join_segments, ["target_id"], "$fk")
      }
    end)
  end

  # The grant store exists only where its references can point: a model declaring no
  # entity types has nothing to grant roles on, and one whose user entity type is absent
  # cannot carry grants at all - which is the state early in a migration history, before
  # the user entity type arrives. Deriving no store there keeps "the empty model has the
  # empty schema" true, the premise a history replayed from empty rests on.
  #
  # Which entity type is the user one comes from the term, not from reflection: a replayed
  # history states the designation as it stood at that point, so a history spanning a
  # rename of the user entity type derives the store at every point rather than losing it
  # until the rename lands.
  defp put_role_grant(%{entities: entities} = model) do
    user_entity = model.user_entity

    if entities == %{} or is_nil(user_entity) or not Map.has_key?(entities, user_entity) do
      entities
    else
      Map.put(entities, RoleGrant, role_grant_entry(model, user_entity))
    end
  end

  # The grant store is derived, never declared: its enum values are the model's entity type
  # modules and role names, and its relationships point at the designated user entity type - so a
  # replayed history derives the store as it stood at that point, with no op declaring it.
  defp role_grant_entry(model, user_entity) do
    entity_types = Map.keys(model.entities)
    global_role_modules = Map.keys(model.roles)

    validate_grant_labels!(entity_types, "entity type")
    validate_grant_labels!(global_role_modules, "global role")

    entity_type_values = Enum.sort_by(entity_types, &Codec.encode(&1, :enum))

    entity_role_names =
      Enum.flat_map(model.entities, fn {_entity_type, entry} ->
        Enum.map(entry.roles, fn {name, _opts} -> name end)
      end)

    role_values =
      entity_role_names
      |> Enum.concat(global_role_modules)
      |> Enum.uniq()
      |> Enum.sort_by(&Codec.encode(&1, :enum))

    %{
      attributes: [
        {:entity_id, :id, [optional: true]},
        {:entity_type, :enum, [optional: true, values: entity_type_values]},
        {:role, :enum, [values: role_values]}
      ],
      relationships: [{:granted_by, user_entity, [optional: true]}, {:user, user_entity, []}],
      roles: [],
      uniques: []
    }
  end

  # A target absent from the model has no outgoing edges - the model is the traversal universe.
  defp required_to_one_targets(model, entity_type) do
    model
    |> Map.get(entity_type, %{relationships: []})
    |> Map.fetch!(:relationships)
    |> Enum.reject(fn {_name, type, opts} ->
      is_list(type) or Keyword.get(opts, :optional) == true
    end)
    |> Enum.map(fn {name, target, _opts} -> {name, target} end)
  end

  # Framework-owned, on every table: the revision each settable column was last set at. The
  # default fills existing rows through the reconciler's add-nullable-fill-tighten path, and is
  # never a DB DEFAULT - a row written after this reads its revisions from whoever wrote it.
  defp revisions_column do
    %{
      name: "$revisions",
      type: :map,
      sql_type: "jsonb",
      collation: nil,
      enum_values: nil,
      default: %{},
      null: false,
      references: nil,
      fk_constraint: nil,
      source: :revisions
    }
  end

  defp reference_column_name(relationship),
    do: fit_identifier([], [Atom.to_string(relationship)], "id")

  defp search_key_columns(attributes) do
    attributes
    |> Enum.filter(fn {_name, type, _opts} -> type == :string end)
    |> Enum.sort()
    |> Enum.map(fn {name, _type, _opts} ->
      %{
        name: fit_identifier([], [Atom.to_string(name)], "$search"),
        type: :string,
        sql_type: "text",
        collation: collation(:string),
        enum_values: nil,
        default: nil,
        null: true,
        references: nil,
        fk_constraint: nil,
        source: {:search_key, name}
      }
    end)
  end

  # A string sorts and compares through its sort key, and an index over it holds the KEY alone - the
  # index plan gives it one when a query sorts or compares by the attribute (see
  # Hologram.DB.IndexPlan). A btree entry is capped at 2704 bytes and the key at 64, while the raw
  # column is unbounded - a composite over both would refuse the writes the column itself accepts,
  # which is why PostgreSQL's own advice for long text is an index over a bounded prefix. The key IS
  # that prefix, stored as a column. The raw column does tie-work only: the planner serves a bound
  # as a range over the key with the pair rechecked on what it returns, and the ordering as an
  # incremental sort within each equal-key group.
  defp sort_key_columns(attributes) do
    attributes
    |> Enum.filter(fn {_name, type, _opts} -> type == :string end)
    |> Enum.sort()
    |> Enum.map(fn {name, _type, _opts} ->
      column_name = fit_identifier([], [Atom.to_string(name)], "$sort")

      %{
        name: column_name,
        type: :string,
        sql_type: "text",
        collation: collation(:string),
        enum_values: nil,
        default: nil,
        null: true,
        references: nil,
        fk_constraint: nil,
        source: {:sort_key, name}
      }
    end)
  end

  defp sql_type(:boolean, _segments, _name), do: "boolean"

  defp sql_type(:date, _segments, _name), do: "date"

  defp sql_type(:datetime, _segments, _name), do: "timestamptz"

  defp sql_type(:enum, segments, name),
    do: fit_identifier(segments, [Atom.to_string(name)], "$enum")

  defp sql_type(:float, _segments, _name), do: "float8"

  defp sql_type(:id, _segments, _name), do: "uuid"

  defp sql_type(:integer, _segments, _name), do: "int8"

  defp sql_type(:string, _segments, _name), do: "text"

  defp sql_type(:time, _segments, _name), do: "time"

  defp sql_type(:uuid, _segments, _name), do: "uuid"

  defp strip_root([root | [_head | _tail] = remainder], root), do: remainder

  defp strip_root(segments, _root), do: segments

  defp stamp_columns do
    Enum.map(@stamp_columns, fn {name, type, sql_type} ->
      %{
        name: name,
        type: type,
        sql_type: sql_type,
        collation: nil,
        enum_values: nil,
        default: nil,
        null: false,
        references: nil,
        fk_constraint: nil,
        source: :system
      }
    end)
  end

  defp validate_column_names!(entity_type, columns) do
    collisions =
      columns
      |> Enum.group_by(& &1.name)
      |> Enum.filter(fn {_name, group} -> length(group) > 1 end)
      |> Enum.sort()

    if collisions != [] do
      descriptions = Enum.map_join(collisions, "\n", &describe_column_collision/1)

      raise Hologram.CompileError,
        message:
          "colliding column names in #{inspect(entity_type)} - rename the declarations so that every derived column name is unique:\n#{descriptions}"
    end

    :ok
  end

  defp validate_derived_names!(mapping, index_entries) do
    entries =
      Enum.flat_map(mapping, fn {entity_type, entity_mapping} ->
        enum_type_entries =
          entity_mapping.columns
          |> Enum.filter(&(&1.type == :enum))
          |> Enum.map(fn column ->
            {:attribute, attribute_name} = column.source

            %{
              kind: "enum type",
              derived_name: column.sql_type,
              declaration: "attribute #{inspect(attribute_name)} in #{inspect(entity_type)}"
            }
          end)

        join_table_entries =
          Enum.map(entity_mapping.join_tables, fn join_table ->
            %{
              kind: "join table",
              derived_name: join_table.name,
              declaration:
                "relationship #{inspect(join_table.relationship)} in #{inspect(entity_type)}"
            }
          end)

        enum_type_entries ++
          join_table_entries ++
          index_name_entries(entity_type, entity_mapping, index_entries[entity_type])
      end)

    shared_names =
      entries
      |> Enum.group_by(&{&1.kind, &1.derived_name})
      |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
      |> Enum.sort()

    # One join table's two objects end in different kinds, so a name its objects alone share
    # comes from two declarations deriving that join table - which its own line reports.
    collisions =
      Enum.reject(shared_names, fn {_key, group} ->
        match?(
          [join_table] when is_binary(join_table),
          group
          |> Enum.map(&Map.get(&1, :join_table))
          |> Enum.uniq()
        )
      end)

    if collisions != [] do
      descriptions =
        Enum.map_join(collisions, "\n", fn {{kind, derived_name}, group} ->
          declarations =
            group
            |> Enum.map(& &1.declaration)
            |> Enum.sort()
            |> Enum.join(", ")

          "  * #{kind} \"#{derived_name}\" is derived from #{declarations}"
        end)

      raise Hologram.CompileError,
        message:
          "colliding derived names - rename the declarations so that every derived name is unique:\n#{descriptions}"
    end

    :ok
  end

  # The grant store's two enums take their values from the MODEL rather than from a declaration,
  # so Hologram.Entity.Validator never meets them: it checks the labels an entity declares - its
  # enum values and its role names - and these two sets are derived from the app's entity type
  # modules and its global role modules. Nothing else asks whether either fits.
  defp validate_grant_labels!(values, description) do
    Enum.each(values, fn value ->
      label = Codec.encode(value, :enum)
      label_size = byte_size(label)

      if label_size > @max_enum_label_bytes do
        raise Hologram.CompileError,
          message:
            "#{description} #{inspect(value)} is too long to store in the role grant store " <>
              "(#{label_size} bytes, limit #{@max_enum_label_bytes}) - shorten the module name"
      end
    end)
  end

  defp validate_model_cycles!(model) do
    {cycles, _visited} =
      model
      |> Map.keys()
      |> Enum.sort()
      |> Enum.reduce({[], MapSet.new()}, fn entity_type, {cycles, visited} ->
        find_cycles(model, entity_type, [], cycles, visited)
      end)

    if cycles != [] do
      descriptions =
        cycles
        |> Enum.map(&canonicalize_cycle/1)
        |> Enum.sort()
        |> Enum.map_join("\n", &describe_cycle/1)

      raise Hologram.CompileError,
        message:
          "cyclic required to-one relationships - no row in such a cycle can ever be created, mark at least one relationship in each cycle as optional: true:\n#{descriptions}"
    end

    :ok
  end
end
