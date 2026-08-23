defmodule Hologram.DB.Mapper do
  @moduledoc false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Codec
  alias Hologram.Entity.Model
  alias Hologram.Reflection

  @hash_bytes 8

  # PostgreSQL truncates identifiers to 63 bytes - derived identifiers must never rely on that.
  @max_identifier_bytes 63

  @doc """
  Returns the column definitions derived from the given entity type module, in physical order:
  id, declared attributes sorted by name, to-one relationship references sorted by name,
  system timestamps.

  Each definition is a map with :name (column name string), :type (the logical attribute type,
  as consumed by the codec), :sql_type (the SQL type name - a derived per-attribute enum type
  name for :enum attributes), :collation (the pinned per-column collation name, nil for types
  that carry none), :enum_values (the declared enum values as strings in declaration order,
  nil for non-enum types), :default (the declared default value, nil when none - creation
  semantics owned by the write path, never a DB DEFAULT), :null (true only for optional
  declarations), :references (the referenced table name for to-one relationship columns,
  nil otherwise), :fk_constraint (the derived `<table>_<column>_$fk` constraint name for
  reference columns, nil otherwise), :index (the derived index name for the columns that
  carry one - `<table>_<column>_$idx` on a to-one reference, which PostgreSQL never indexes
  automatically, and `<table>_<attribute>_$sort_$idx` on a sort-key companion, so an ordering
  or a comparison on the attribute is served from the key rather than from a sort - nil
  otherwise), and :source (:system, or the declaration the column is derived from).
  To-many relationships derive no columns - they live in join tables.

  Each :string attribute derives a nullable `<attribute>_$sort` companion column (source
  `{:sort_key, name}`) holding the attribute's derived sort key - the order both executors
  sort and compare the attribute by. It is a column like any other the mapping derives:
  migrations create, rename and drop it with its attribute.

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
  Derives the complete physical name mapping for the given entity type modules.

  Runs every derivation check exactly once - table name collisions, required to-one cycles,
  per-entity column collisions, and cross-entity within-kind derived name collisions (join
  tables and enum types, whose single-underscore seams can merge to the same name across
  entities) - and returns a map from entity type module to its mapping: :table (the table
  name), :pk_constraint (the derived `<table>_$pk` constraint name), :columns (as returned
  by columns/1), :indexes (index name to %{columns:, nulls_distinct:, unique:} - a
  `<table>_<attribute>_$uidx` entry per `unique: true` attribute, plus the role grant store's
  framework-owned one), and :join_tables (as returned by join_tables/1).
  """
  @spec derive!(list(module)) :: %{module => %{atom => any}}
  def derive!(entity_types) do
    # The collision check is a pure function of the module atoms - running it before
    # reflection keeps its readable error ahead of any missing-module crash.
    validate_table_names!(entity_types)

    entity_types
    |> Model.from_modules(Reflection.list_roles())
    |> derive_from_model!()
  end

  @doc """
  Derives the complete physical name mapping for the given model term.

  Same checks and result shape as derive!/1, plus the role grant store, whose entry is
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

    mapping =
      Map.new(entities, fn {entity_type, entry} ->
        table_name = table_name(entity_type)

        {entity_type,
         %{
           table: table_name,
           pk_constraint: fit_identifier("#{table_name}_$pk"),
           columns: columns_from_entry(entity_type, entry),
           indexes: entity_indexes(entity_type, entry, table_name),
           join_tables: join_tables_from_entry(entity_type, entry)
         }}
      end)

    validate_derived_names!(mapping)

    mapping
  end

  @doc """
  Returns the given identifier unchanged when it fits the PostgreSQL identifier limit,
  or shortened to a readable prefix followed by a short deterministic hash of the full
  identifier otherwise.
  """
  @spec fit_identifier(String.t()) :: String.t()
  def fit_identifier(identifier) do
    if byte_size(identifier) > @max_identifier_bytes do
      hash =
        :md5
        |> :crypto.hash(identifier)
        |> Base.encode16(case: :lower)
        |> binary_part(0, @hash_bytes)

      prefix_bytes = @max_identifier_bytes - @hash_bytes - 1

      binary_part(identifier, 0, prefix_bytes) <> "_" <> hash
    else
      identifier
    end
  end

  @doc """
  Returns the join table definitions derived from the given entity type module's to-many
  relationships, sorted by relationship name.

  Each definition is a map with :name (the join table name - `<source_table>_<relationship>_$join`
  per the derived-name system), :relationship (the declaring relationship name), :source_table,
  :target_table, :reverse_index (the name of the index over (target_id, source_id)),
  :pk_constraint, :source_fk_constraint, and :target_fk_constraint (the derived constraint
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
  Returns the table name derived from the given entity type module.

  The name is the snake_cased module path with the leading segment stripped when it matches
  the primary OTP app's conventional root namespace - modules from other roots (guest apps,
  libraries) keep their full path. Derived names over the PostgreSQL identifier limit keep
  a readable prefix followed by a short deterministic hash of the full name.

  Framework-provided entity types are pinned to their full snake_cased path, so their
  tables carry the hologram_ prefix in every project - path derivation would strip it
  inside the framework's own repository, where the root namespace is Hologram.
  """
  @spec table_name(module) :: String.t()
  def table_name(Hologram.Auth.RoleGrant), do: "hologram_role_grant"

  def table_name(entity_type) do
    segments = Module.split(entity_type)

    root =
      Reflection.otp_app()
      |> Atom.to_string()
      |> Macro.camelize()

    segments
    |> strip_root(root)
    |> Enum.map_join("_", &Macro.underscore/1)
    |> fit_identifier()
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
    table_name = table_name(entity_type)

    attribute_columns =
      Enum.map(entry.attributes, fn {name, type, opts} ->
        %{
          name: Atom.to_string(name),
          type: type,
          sql_type: sql_type(type, table_name, name),
          collation: collation(type),
          enum_values: enum_values(type, opts),
          default: Keyword.get(opts, :default),
          null: Keyword.get(opts, :optional) == true,
          references: nil,
          fk_constraint: nil,
          index: nil,
          source: {:attribute, name}
        }
      end)

    to_one_columns =
      entry.relationships
      |> Enum.reject(fn {_name, type, _opts} -> is_list(type) end)
      |> Enum.map(fn {name, target, opts} ->
        %{
          name: fit_identifier("#{name}_id"),
          type: :uuid,
          sql_type: "uuid",
          collation: nil,
          enum_values: nil,
          default: nil,
          null: Keyword.get(opts, :optional) == true,
          references: table_name(target),
          fk_constraint: fit_identifier("#{table_name}_#{name}_id_$fk"),
          index: fit_identifier("#{table_name}_#{name}_id_$idx"),
          source: {:relationship, name}
        }
      end)

    sort_columns = sort_key_columns(table_name, entry.attributes)

    columns =
      [id_column() | attribute_columns] ++ to_one_columns ++ timestamp_columns() ++ sort_columns

    validate_column_names!(entity_type, columns)

    columns
  end

  defp describe_column_collision({name, group}) do
    sources =
      Enum.map_join(group, ", ", fn column ->
        {kind, declaration_name} = column.source
        "#{kind} #{inspect(declaration_name)}"
      end)

    "  * column \"#{name}\" is derived from #{sources}"
  end

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
  # The index is over the raw column, so a string value is bounded by the btree entry limit -
  # the validator refuses a unique string above it, so the engine never gets to. The sort-key
  # companion sidesteps the same limit by indexing a bounded key, which a unique index cannot
  # do: a prefix is not unique.
  # TODO: a unique index over a hash expression lifts the bound for unbounded strings, once a
  # declaration needs it - it teaches the whole index chain an expression shape.
  defp entity_indexes(entity_type, entry, table_name) do
    entry.attributes
    |> Enum.filter(fn {_name, _type, opts} -> Keyword.get(opts, :unique) == true end)
    |> Map.new(fn {name, _type, _opts} ->
      {fit_identifier("#{table_name}_#{name}_$uidx"),
       %{columns: [Atom.to_string(name)], nulls_distinct: true, unique: true}}
    end)
    |> Map.merge(framework_indexes(entity_type))
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

  # The role grant store carries the one index no declaration derives: unique over the grant
  # fact, with nulls compared as values - resource_type and resource_id nils encode the
  # type-wide and global grant shapes, so identical rows with nils must still collide.
  defp framework_indexes(Hologram.Auth.RoleGrant) do
    %{
      "hologram_role_grant_$uidx" => %{
        columns: ["user_id", "resource_type", "resource_id", "role"],
        nulls_distinct: false,
        unique: true
      }
    }
  end

  defp framework_indexes(_entity_type), do: %{}

  defp id_column do
    %{
      name: "id",
      type: :uuid,
      sql_type: "uuid",
      collation: nil,
      enum_values: nil,
      default: nil,
      null: false,
      references: nil,
      fk_constraint: nil,
      index: nil,
      source: :system
    }
  end

  defp join_tables_from_entry(entity_type, entry) do
    source_table = table_name(entity_type)

    entry.relationships
    |> Enum.filter(fn {_name, type, _opts} -> is_list(type) end)
    |> Enum.map(fn {name, [target], _opts} ->
      join_table_name = fit_identifier("#{source_table}_#{name}_$join")

      %{
        name: join_table_name,
        relationship: name,
        source_table: source_table,
        target_table: table_name(target),
        reverse_index: fit_identifier("#{join_table_name}_target_id_$idx"),
        pk_constraint: fit_identifier("#{join_table_name}_$pk"),
        source_fk_constraint: fit_identifier("#{join_table_name}_source_id_$fk"),
        target_fk_constraint: fit_identifier("#{join_table_name}_target_id_$fk")
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

  # The grant store is derived, never declared: its enum values are the model's table names
  # and role names, and its relationships point at the designated user entity type - so a
  # replayed history derives the store as it stood at that point, with no op declaring it.
  defp role_grant_entry(model, user_entity) do
    resource_type_values =
      model.entities
      |> Map.keys()
      |> Enum.map(&RoleGrant.resource_type/1)
      |> Enum.sort()

    entity_role_names =
      Enum.flat_map(model.entities, fn {_entity_type, entry} ->
        Enum.map(entry.roles, fn {name, _opts} -> name end)
      end)

    role_values =
      entity_role_names
      |> Enum.concat(Map.keys(model.roles))
      |> Enum.uniq()
      |> Enum.sort_by(&Codec.encode(&1, :enum))

    %{
      attributes: [
        {:resource_id, :uuid, [optional: true]},
        {:resource_type, :enum, [optional: true, values: resource_type_values]},
        {:role, :enum, [values: role_values]}
      ],
      relationships: [{:granted_by, user_entity, [optional: true]}, {:user, user_entity, []}],
      roles: []
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

  # The companion's index holds the KEY alone. A btree entry is capped at 2704 bytes and the key
  # at 64, while the raw column is unbounded - a composite over both would refuse the writes the
  # column itself accepts, which is why PostgreSQL's own advice for long text is an index over a
  # bounded prefix. The key IS that prefix, stored as a column. The raw column does tie-work only:
  # the planner serves a bound as a range over the key with the pair rechecked on what it returns,
  # and the ordering as an incremental sort within each equal-key group. It rides the column so
  # that creation, rename and drop follow the column through the machinery the reference index
  # already uses.
  defp sort_key_columns(table_name, attributes) do
    attributes
    |> Enum.filter(fn {_name, type, _opts} -> type == :string end)
    |> Enum.sort()
    |> Enum.map(fn {name, _type, _opts} ->
      %{
        name: fit_identifier("#{name}_$sort"),
        type: :string,
        sql_type: sql_type(:string, table_name, name),
        collation: collation(:string),
        enum_values: nil,
        default: nil,
        null: true,
        references: nil,
        fk_constraint: nil,
        index: fit_identifier("#{table_name}_#{name}_$sort_$idx"),
        source: {:sort_key, name}
      }
    end)
  end

  defp sql_type(:boolean, _table_name, _name), do: "boolean"

  defp sql_type(:date, _table_name, _name), do: "date"

  defp sql_type(:datetime, _table_name, _name), do: "timestamptz"

  defp sql_type(:enum, table_name, name), do: fit_identifier("#{table_name}_#{name}_$enum")

  defp sql_type(:float, _table_name, _name), do: "float8"

  defp sql_type(:integer, _table_name, _name), do: "int8"

  defp sql_type(:string, _table_name, _name), do: "text"

  defp sql_type(:uuid, _table_name, _name), do: "uuid"

  defp strip_root([root | [_head | _tail] = remainder], root), do: remainder

  defp strip_root(segments, _root), do: segments

  defp timestamp_columns do
    Enum.map(["created_at", "updated_at"], fn name ->
      %{
        name: name,
        type: :datetime,
        sql_type: "timestamptz",
        collation: nil,
        enum_values: nil,
        default: nil,
        null: false,
        references: nil,
        fk_constraint: nil,
        index: nil,
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

  defp validate_derived_names!(mapping) do
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

        enum_type_entries ++ join_table_entries
      end)

    collisions =
      entries
      |> Enum.group_by(&{&1.kind, &1.derived_name})
      |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
      |> Enum.sort()

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
