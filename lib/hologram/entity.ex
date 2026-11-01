defmodule Hologram.Entity do
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.AST
  alias Hologram.Entity
  alias Hologram.Entity.Expression
  alias Hologram.Entity.NotIncluded
  alias Hologram.Entity.ServerOnly
  alias Hologram.Entity.Validator
  alias Hologram.Job
  alias Hologram.Policy.Expression, as: PolicyExpression
  alias Hologram.Reflection

  @system_attributes [
    {:created_at, :datetime, []},
    {:id, :uuid, []},
    {:updated_at, :datetime, []}
  ]

  @typedoc """
  An entity id - the canonical lowercase 8-4-4-4-12 spelling generate_id/0 mints.
  """
  @type id :: String.t()

  @typedoc """
  An entity operation - an atom, or a grant lifecycle operation naming the role (or roles) it covers.
  """
  @type operation :: atom | {atom, atom | list(atom)}

  @typedoc """
  An entity struct - a struct of a module that uses Hologram.Entity.
  The entity types cannot be named here, since the framework is compiled before any of them exist.
  """
  @type t :: struct

  defmacro __using__(opts) do
    Validator.validate_use_opts!(__CALLER__.module, opts)

    [
      quote do
        import Hologram.Entity,
          only: [
            allow: 1,
            allow: 2,
            attribute: 2,
            attribute: 3,
            relationship: 2,
            relationship: 3,
            role: 1,
            role: 2
          ]

        import Hologram.Policy, only: [policy: 1]

        @before_compile Entity

        @doc """
        Returns true to indicate that the callee module is an entity type module (has "use Hologram.Entity" directive).

        ## Examples

            iex> __is_hologram_entity__()
            true
        """
        @spec __is_hologram_entity__() :: boolean
        def __is_hologram_entity__, do: true

        @doc """
        Builds a new entity struct of this entity type from the given values (a map or a keyword list).
        The id is generated unless provided, declared attribute defaults are applied to absent attributes, and system timestamps are nil.
        To-one references are set via their `<name>_id` fields - relationship values themselves cannot be assigned at construction.
        """
        @spec new(%{optional(atom) => any} | keyword) :: t
        def new(values \\ []), do: Hologram.Entity.new(__MODULE__, values)

        defoverridable new: 0, new: 1
      end,
      register_attributes_accumulator(),
      register_policies_accumulator(),
      register_policy_sources_accumulator(),
      register_role_declarations_accumulator(),
      register_relationships_accumulator(),
      register_inverse_relationships_accumulator(),
      register_relationship_locations_accumulator(),
      register_roles_attribute()
    ] ++ user_entity_marker(opts)
  end

  defmacro __before_compile__(env) do
    Validator.validate_roles!(env.module)

    system_attributes =
      @system_attributes
      |> Enum.sort()
      |> Macro.escape()

    struct_fields =
      env.module
      |> struct_fields()
      |> Macro.escape()

    struct_type = struct_type(env.module)

    [
      quote do
        # The metadata struct is expanded HERE, in the entity's own module body, so the module
        # carries a compile-time dependency on it. Escaping a pre-built one instead bakes a copy of
        # whatever shape it had when the FRAMEWORK compiled, and an incremental build never
        # revisits it: a field added to the metadata would leave every entity holding the old
        # shape, disagreeing with a freshly constructed one for as long as the build lasts.
        defstruct Enum.sort([
                    {:__meta__, %Hologram.Entity.Metadata{}} | unquote(struct_fields)
                  ])

        @typedoc """
        An entity struct of this entity type.
        Every attribute field admits nil - a struct carries whatever it was built with, and declarations are checked at the write.
        """
        @type t :: unquote(struct_type)

        @doc """
        Returns the list of attribute definitions for the compiled entity type, sorted by attribute name.
        """
        @spec __attributes__() :: list({atom, atom, keyword})
        def __attributes__, do: Enum.sort(@__attributes__)

        @doc """
        Returns the list of policy definitions for the compiled entity type, in declaration order.
        Policy rules are OR'd, so the order carries no semantics - it is preserved to keep reflection output readable against the source.
        """
        @spec __policies__() ::
                list({Hologram.Entity.operation(), term, atom | {atom, atom} | nil, keyword})
        def __policies__, do: Enum.reverse(@__policies__)

        @doc false
        @spec __policy_sources__() :: list(module)
        def __policy_sources__, do: Enum.reverse(@__policy_sources__)

        @doc """
        Returns the list of relationship definitions for the compiled entity type, sorted by relationship name.
        Inverse relationships are listed apart, with the inverse relationship definitions.
        """
        @spec __relationships__() :: list({atom, module | list(module), keyword})
        def __relationships__, do: Enum.sort(@__relationships__)

        @doc false
        @spec __role_declarations__() :: list({atom, keyword, module})
        def __role_declarations__, do: Enum.reverse(@__role_declarations__)

        @doc """
        Returns the list of role definitions for the compiled entity type, sorted by role name.
        """
        @spec __roles__() :: list({atom, keyword})
        def __roles__, do: Enum.sort(@__roles__)

        @doc """
        Returns the list of system attribute definitions present on every entity type, sorted by attribute name.
        """
        @spec __system_attributes__() :: list({atom, atom, keyword})
        def __system_attributes__, do: unquote(system_attributes)
      end,
      relationship_reflection()
    ]
  end

  @doc """
  Accumulates the given policy definition in __policies__ module attribute.

  An allow line grants the given operation, and every key on it is an option:

    * `to:` - who holds the operation: a role name (`:editor`), a global role module (`Admin`), a
      role held on the row a to-one relationship, or a path of them, points at as
      `{role, relationship}` (`{:editor, project}`, `{:owner, trip.user}`), a role held on a whole
      entity type as `{role, entity type}` (`{:moderator, MyApp.Post}`), or a list of them, any
      one of which suffices.
    * `via:` - a to-one relationship, written as a bare name (`via: project`), or a path of them
      (`via: trip.user`): the operation is granted when the same operation is granted on the row
      it leads to. Written as `{operation, relationship}` (`via: {:update, project}`,
      `via: {:update, stop.trip}`), it is granted when the named operation is granted on that
      row. A create rule names one when the related type's own create rule says nothing about who
      may add to an existing row, as on a type whose rows nobody holds a role on before they exist.
    * `when:` - a condition on the row: `when: priority < 3 and archived == false`,
      `when: owner_id == nil or owner_id == user_id()`. A bare name is an attribute of the row,
      on either side of a comparison, so `when: guests <= capacity` compares two attributes, `^`
      marks a value from the surrounding code (`^@max_priority`), literals need nothing, and
      `user_id()` is the acting user's entity id. The operators are `==`, `!=`, `<`, `<=`, `>`,
      `>=`, `in`, `not in`, `and` and `or`, `and` binding tighter and parentheses grouping. A
      dotted name is a path through to-one relationships, read off the row they lead to,
      `when: project.archived == false`, through as many relationships as it names. The rows along
      a path are read as stored, whatever the acting user may read of them. A path that leads
      nowhere - an empty relationship or a reference to a row that is gone - reads as nil, so `!=`
      and `not in` admit a row whose path ends nowhere: `project.archived != true` holds for a task
      with no project. A condition that wants the related row there says so,
      `project.id != nil and project.archived != true`. A condition built from data goes in pinned,
      `when: ^predicates`, as a list of predicates pairing names with values, where an `or:` entry
      holding two or more predicate lists is a disjunction.

  The options on one line must all hold at once, and several lines for one operation are
  alternatives.
  A line with no options grants the operation unconditionally.

  A client that checks permissions holds the related rows its checks read - the row a `via:` leads
  to and the rows the rules it asks read through it, the rows before the last relationship of a
  `to:` reference, the rows along a `when:` path - beside the rows it holds, read under the session
  user's own read rules and kept current. A row the user may not read is missing there and compares
  as nil, and a change to a related row answers the check again.

  So a rule that reads a related row through an entity type with no read rules fails the build: no
  client ever holds such a row, and the browser would answer no where the server may answer yes. A
  rule for `:read` itself is exempt, since a row reaches a client only once the server's read rules
  admitted it, and a client never decides them.
  """
  @spec allow(operation, T.opts()) :: Macro.t()
  defmacro allow(operation, spec \\ []) do
    spec = PolicyExpression.spec(operation, spec, __CALLER__)

    quote do
      Entity.__put_policy__(__MODULE__, unquote(operation), unquote(spec), __MODULE__)
    end
  end

  @doc """
  Accumulates the given attribute definition in __attributes__ module attribute.
  """
  @spec attribute(atom, atom, T.opts()) :: Macro.t()
  defmacro attribute(name, type, opts \\ []) do
    quote do
      name = unquote(name)
      type = unquote(type)
      opts = unquote(opts)

      Validator.validate_attribute!(__MODULE__, name, type, opts)
      Module.put_attribute(__MODULE__, :__attributes__, {name, type, opts})
    end
  end

  @doc """
  Accumulates the given relationship definition - in __relationships__ module attribute, or in
  __inverse_relationships__ module attribute for an inverse.
  A relationship is to-one when its type is a module and to-many when its type is a one-element list wrapping a module.

  The options:

    * `inverse:` - the relationship is the inverse of one the related type declares, named bare:
      `relationship :messages, [Message], inverse: channel` holds the messages whose `channel`
      is the row, `relationship :posts, [Post], inverse: tags` the posts whose `tags` hold it,
      and `relationship :profile, Profile, inverse: user` the one profile whose `user` is the
      row. An inverse stores nothing of its own, so declaring or removing one never moves data,
      and it is read-only: a write goes to the row that stores the fact, and a path in a
      condition, `via:` and the relationship of a `to:` reference go through stored to-ones only.
      It takes no `optional:` or `unique:`, since the relationship it reverses carries both.
    * `optional:` - a to-one may reference nothing, its reference holding nil.
    * `sort:` - the order of an inverse set, named bare and read on the related type:
      `sort: created_at`, `sort: [created_at: :desc]`.
    * `unique:` - no two rows of the entity type reference the same row, enforced in the
      database and reported by the write verbs as `:unique` on the `<name>_id` field. To-one
      only. An optional unique to-one admits any number of rows referencing nothing.

  `inverse:` and `sort:` name the related type's vocabulary and are written in place on the line.
  A value chosen in the surrounding code is pinned, `inverse: ^name`.
  """
  @spec relationship(atom, module | list(module), T.opts()) :: Macro.t()
  defmacro relationship(name, type, opts \\ []) do
    lowered_opts = Expression.relationship_opts(opts, __CALLER__)
    location = {__CALLER__.file, __CALLER__.line}

    quote do
      Entity.__put_relationship__(
        __MODULE__,
        unquote(name),
        unquote(type),
        unquote(lowered_opts),
        unquote(location)
      )
    end
  end

  @doc """
  Accumulates the given role definition in __roles__ module attribute.
  A role is a named grantable capability set of the entity type - role names live in their own namespace, separate from attribute and relationship names.
  A role name is one role however many places declare it, here and in the policies the entity type takes on: extends targets union, and granted_to follows the last declaration mentioning it.
  """
  @spec role(atom, T.opts()) :: Macro.t()
  defmacro role(name, opts \\ []) do
    quote do
      Entity.__put_role__(__MODULE__, unquote(name), unquote(opts), __MODULE__)
    end
  end

  @doc """
  Returns the given role name together with every role of the given entity type whose extends chain reaches it, sorted.
  A role that extends another one carries all of its capabilities, so a requirement for the given role is satisfied by every role in the returned list.
  """
  @spec expand_role(module, atom) :: list(atom)
  def expand_role(entity_type, role_name) do
    extends_by_name =
      Map.new(entity_type.__roles__(), fn {name, opts} ->
        {name, List.wrap(Keyword.get(opts, :extends, []))}
      end)

    expand_role_names(MapSet.new([role_name]), extends_by_name)
  end

  @doc """
  Generates a new entity id - a UUIDv7 string built from the number of milliseconds since the Unix epoch (1970-01-01 UTC, 48 bits) followed by random bits (74 bits).
  Entity ids come only from this function, on the server and on the client alike.
  """
  @spec generate_id() :: id
  def generate_id do
    unix_ms = System.system_time(:millisecond)
    <<rand_a::12, rand_b::62, _discarded::6>> = :crypto.strong_rand_bytes(10)

    uuid = <<unix_ms::48, 7::4, rand_a::12, 2::2, rand_b::62>>

    <<part_1::binary-size(8), part_2::binary-size(4), part_3::binary-size(4),
      part_4::binary-size(4), part_5::binary-size(12)>> = Base.encode16(uuid, case: :lower)

    "#{part_1}-#{part_2}-#{part_3}-#{part_4}-#{part_5}"
  end

  @doc """
  Builds a new entity struct of the given entity type from the given values (a map or a keyword list).
  The id is generated unless provided, declared attribute defaults are applied to absent attributes, and system timestamps are nil.
  To-one references are set via their `<name>_id` fields - relationship values themselves cannot be assigned at construction.
  This is the form for an entity type held in a variable - a type written by name has its own generated new/1, which delegates here.
  """
  @spec new(module, %{optional(atom) => any} | keyword) :: t
  def new(entity_type, values \\ %{}) do
    values_map = Map.new(values)

    Validator.validate_writable!(entity_type)
    validate_construction_values!(entity_type, values_map)

    fields = Map.put_new(values_map, :id, generate_id())

    struct!(entity_type, fields)
  end

  @doc false
  @spec __put_policy__(module, operation, T.opts(), module) :: :ok
  def __put_policy__(module, operation, spec, source) do
    Validator.validate_allow!(module, operation, spec)

    policy =
      {operation, Keyword.get(spec, :to), Keyword.get(spec, :via), Keyword.get(spec, :when, [])}

    Module.put_attribute(module, :__policies__, policy)
    Module.put_attribute(module, :__policy_sources__, source)

    :ok
  end

  # An inverse goes into a list of its own: every reader of the stored relationships reads what a
  # row stores, and an inverse stores nothing. Where each line was written is kept for the checks
  # made once every entity type is compiled, whose messages point at the line the way a compile
  # error does.
  @doc false
  @spec __put_relationship__(module, atom, any, T.opts(), {String.t(), pos_integer}) :: :ok
  def __put_relationship__(module, name, type, opts, location) do
    Validator.validate_relationship!(module, name, type, opts)

    accumulator =
      if Keyword.has_key?(opts, :inverse),
        do: :__inverse_relationships__,
        else: :__relationships__

    Module.put_attribute(module, accumulator, {name, type, opts})
    Module.put_attribute(module, :__relationship_locations__, {name, location})

    :ok
  end

  # A role name is one role, however many places declare it - a policy taken on, another policy
  # nested inside it, and the entity type itself. The RAW declarations are kept beside the merged
  # list, because a merged entry cannot say which source declared which extends target, which is
  # what an error message about one of them has to name.
  # Every declaration is validated, then merged:
  # extends unions, and granted_to follows the LAST declaration that mentions it, a declaration
  # that omits it having no opinion. Merged options are sorted, so the entry does not depend on
  # which side declared what.
  @doc false
  @spec __put_role__(module, atom, T.opts(), module) :: :ok
  def __put_role__(module, name, opts, source) do
    Validator.validate_role!(module, name, opts)

    Module.put_attribute(module, :__role_declarations__, {name, opts, source})

    declarations = Module.get_attribute(module, :__roles__)

    Module.put_attribute(module, :__roles__, put_role_declaration(declarations, name, opts))

    :ok
  end

  # How a refusal names where the fact behind a declared inverse lives: the reference column of the
  # related type for an inverse of a to-one, the related type's relationship for an inverse of a
  # to-many.
  @doc false
  @spec describe_inverse(module, atom) :: String.t()
  def describe_inverse(entity_type, name) do
    inverse = inverse_relationship(entity_type, name)

    if inverse.reference? do
      "the #{inverse.forward}_id reference of #{inspect(inverse.target)}"
    else
      "the #{inverse.forward} relationship of #{inspect(inverse.target)}"
    end
  end

  # The fields of the entity type that can hold embedded rows: its stored relationships and its
  # inverses.
  @doc false
  @spec includable_names(module) :: list(atom)
  def includable_names(entity_type) do
    entity_type.__relationships__()
    |> Enum.concat(entity_type.__inverse_relationships__())
    |> Enum.map(fn {name, _type, _opts} -> name end)
    |> Enum.sort()
  end

  # What an inverse reads: the related type, the relationship it reverses there and whether
  # that one is a to-one (read from its reference column) or a to-many (read from its join table),
  # the declared order in the sort stage's data form, and whether the inverse is a set. Nil for a
  # name that is no inverse of the entity type. The related type has to be compiled and to declare
  # the reversed relationship.
  @doc false
  @spec inverse_relationship(module, atom) ::
          %{
            forward: atom,
            reference?: boolean,
            sort: atom | list,
            target: module,
            to_many?: boolean
          }
          | nil
  def inverse_relationship(entity_type, name) do
    case Enum.find(entity_type.__inverse_relationships__(), &(elem(&1, 0) == name)) do
      {_name, type, opts} ->
        target =
          type
          |> List.wrap()
          |> hd()

        forward = Keyword.fetch!(opts, :inverse)

        %{
          forward: forward,
          reference?: not is_list(relationship_target(target, forward)),
          sort: Keyword.get(opts, :sort, []),
          target: target,
          to_many?: is_list(type)
        }

      nil ->
        nil
    end
  end

  # The inverses of the entity type reversing the given to-many of another type - the sets a client
  # files under this type's rows that an edge of that relationship moves. The relationship comes
  # by name as an effect spells it, so a name this node never compiled matches nothing.
  @doc false
  @spec inverses_of_to_many(module, module, String.t()) :: list(atom)
  def inverses_of_to_many(entity_type, forward_type, forward_name) do
    entity_type.__inverse_relationships__()
    |> Enum.map(fn {name, _type, _opts} -> {name, inverse_relationship(entity_type, name)} end)
    |> Enum.filter(fn {_name, inverse} ->
      not inverse.reference? and inverse.target == forward_type and
        Atom.to_string(inverse.forward) == forward_name
    end)
    |> Enum.map(fn {name, _inverse} -> name end)
  end

  # One row read twice - at the root and as another row's embed, or by two queries of one render -
  # arrives as two copies whose includes differ. The kept copy keeps its values and takes every
  # relationship it did not include from the other one, so whichever copy is met first, the row
  # carries what either included.
  @doc false
  @spec merge_copies(struct, struct) :: struct
  def merge_copies(%entity_type{} = kept, copy) do
    entity_type
    |> includable_names()
    |> Enum.reduce(kept, fn name, merged ->
      case {Map.fetch!(merged, name), Map.fetch!(copy, name)} do
        {%NotIncluded{}, included} -> Map.put(merged, name, included)
        {_included, _other} -> merged
      end
    end)
  end

  @doc false
  @spec register_attributes_accumulator() :: AST.t()
  def register_attributes_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__attributes__, accumulate: true)
    end
  end

  @doc false
  @spec register_inverse_relationships_accumulator() :: AST.t()
  def register_inverse_relationships_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__inverse_relationships__, accumulate: true)
    end
  end

  @doc false
  @spec register_policies_accumulator() :: AST.t()
  def register_policies_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__policies__, accumulate: true)
    end
  end

  @doc false
  @spec register_policy_sources_accumulator() :: AST.t()
  def register_policy_sources_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__policy_sources__, accumulate: true)
    end
  end

  @doc false
  @spec register_relationship_locations_accumulator() :: AST.t()
  def register_relationship_locations_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__relationship_locations__, accumulate: true)
    end
  end

  @doc false
  @spec register_relationships_accumulator() :: AST.t()
  def register_relationships_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__relationships__, accumulate: true)
    end
  end

  @doc false
  @spec register_role_declarations_accumulator() :: AST.t()
  def register_role_declarations_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__role_declarations__, accumulate: true)
    end
  end

  @doc false
  @spec register_roles_attribute() :: AST.t()
  def register_roles_attribute do
    quote do
      @__roles__ []
    end
  end

  # The type a chain of relationships leads to - each followed to the type its rows are, so a chain
  # may pass through a to-many or an inverse as well as a to-one.
  @doc false
  @spec path_target(module, list(atom)) :: module
  def path_target(entity_type, relationship_names) do
    Enum.reduce(relationship_names, entity_type, &related_type(&2, &1))
  end

  # The type the rows of a relationship are: a stored to-one's target, a stored to-many's element
  # type, or an inverse's target, single or set.
  @doc false
  @spec related_type(module, atom) :: module
  def related_type(entity_type, name) do
    case inverse_relationship(entity_type, name) do
      %{target: target} ->
        target

      nil ->
        entity_type
        |> relationship_target(name)
        |> List.wrap()
        |> hd()
    end
  end

  @doc false
  @spec relationship_target(module, atom) :: module | list(module)
  def relationship_target(entity_type, relationship_name) do
    {_name, target_type, _opts} =
      Enum.find(entity_type.__relationships__(), fn {name, _target, _opts} ->
        name == relationship_name
      end)

    target_type
  end

  defp merge_role_opts(declared_opts, opts) do
    extends =
      [declared_opts, opts]
      |> Enum.flat_map(&List.wrap(&1[:extends]))
      |> Enum.uniq()
      |> Enum.sort()

    granted_to =
      if Keyword.has_key?(opts, :granted_to) do
        opts[:granted_to]
      else
        declared_opts[:granted_to]
      end

    Enum.reject([extends: extends, granted_to: granted_to], fn {_key, value} ->
      value in [[], nil]
    end)
  end

  # granted_to: nil is the neutral spelling of "no grant" - the same fact as never mentioning
  # the option - so it is dropped rather than stored, and one role has one spelling of it.
  # Nothing else is normalized here: a first declaration keeps extends exactly as written, and
  # only a merge turns it into a list.
  # A new name is PREPENDED, which is what the accumulating attribute did before: both readers
  # of :__roles__ (the generated __roles__/0 and Validator.validate_roles!/1) sort, so the
  # stored order carries nothing.
  defp put_role_declaration(declarations, name, opts) do
    if Keyword.has_key?(declarations, name) do
      Enum.map(declarations, fn
        {^name, declared_opts} -> {name, merge_role_opts(declared_opts, opts)}
        declaration -> declaration
      end)
    else
      kept_opts =
        Keyword.reject(opts, fn {key, value} -> key == :granted_to and is_nil(value) end)

      [{name, kept_opts} | declarations]
    end
  end

  @doc false
  @spec server_only_attribute_names(module) :: list(atom)
  def server_only_attribute_names(entity_type) do
    entity_type.__attributes__()
    |> Enum.filter(fn {_name, _type, opts} -> opts[:server_only] == true end)
    |> Enum.map(fn {name, _type, _opts} -> name end)
  end

  @doc false
  @spec strip_server_only(t) :: t
  def strip_server_only(entity) do
    attribute_names = server_only_attribute_names(entity.__struct__)

    Enum.reduce(attribute_names, entity, fn name, stripped ->
      %{stripped | name => %ServerOnly{attribute: name}}
    end)
  end

  # Sentinels are terminal - they hold no entity structs, and re-walking one would rebuild it
  # for nothing.
  @doc false
  @spec strip_server_only_deep(any) :: any
  def strip_server_only_deep(%NotIncluded{} = term), do: term

  def strip_server_only_deep(%ServerOnly{} = term), do: term

  def strip_server_only_deep(term) when is_struct(term) do
    stripped =
      if Reflection.entity?(term.__struct__) do
        strip_server_only(term)
      else
        term
      end

    walked_fields =
      stripped
      |> Map.from_struct()
      |> Map.new(fn {name, value} -> {name, strip_server_only_deep(value)} end)

    Map.merge(stripped, walked_fields)
  end

  # Keys are walked as well as values - any term can key a map, an entity struct included.
  def strip_server_only_deep(term) when is_map(term) do
    Map.new(term, fn {key, value} ->
      {strip_server_only_deep(key), strip_server_only_deep(value)}
    end)
  end

  def strip_server_only_deep(term) when is_list(term) do
    strip_server_only_deep_list(term)
  end

  def strip_server_only_deep(term) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.map(&strip_server_only_deep/1)
    |> List.to_tuple()
  end

  def strip_server_only_deep(term), do: term

  # Everything the entity DECLARES, sorted by name. The framework's own __meta__ field is added
  # by the caller rather than here, so that its struct is expanded in the entity's module.
  # An attribute field holds what its declaration declares as the default, so a bare struct
  # agrees with new/2 on everything but the id - which only the constructor can mint, a struct
  # default being evaluated once, at compile time.
  @doc false
  # sobelow_skip ["DOS.BinToAtom"]
  @spec struct_fields(module) :: list({atom, any})
  def struct_fields(module) do
    system_attribute_fields =
      Enum.map(@system_attributes, fn {name, _type, _opts} -> {name, nil} end)

    attribute_fields =
      module
      |> Module.get_attribute(:__attributes__)
      |> Enum.map(fn {name, _type, opts} -> {name, Keyword.get(opts, :default)} end)

    relationship_fields =
      module
      |> Module.get_attribute(:__relationships__)
      |> Enum.flat_map(fn
        {name, [_target], _opts} ->
          [{name, %NotIncluded{relationship: name}}]

        {name, _target, _opts} ->
          # Compile-time atom creation - the reference field atoms are being defined here.
          # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
          [{:"#{name}_id", nil}, {name, %NotIncluded{relationship: name}}]
      end)

    # An inverse stores no reference, so it holds the one field its rows are embedded in.
    inverse_fields =
      module
      |> Module.get_attribute(:__inverse_relationships__)
      |> Enum.map(fn {name, _type, _opts} -> {name, %NotIncluded{relationship: name}} end)

    Enum.sort(
      system_attribute_fields ++ attribute_fields ++ relationship_fields ++ inverse_fields
    )
  end

  @doc """
  Validates the given entity struct against its entity type's declarations - attribute types, enum values, required presence, the declared constraint options, and to-one references (required presence, canonical entity id format).
  Returns :ok, or {:error, violations} where violations maps each violating field name to the list of its violation reasons, all violations accumulated.
  """
  @spec validate(t) :: :ok | {:error, %{atom => list(atom | {atom, any})}}
  def validate(entity) when is_struct(entity) do
    entity_type = entity.__struct__
    data = Map.take(entity, validated_field_names(entity_type))

    entity_type
    |> Validator.validate(data)
    |> group_errors()
  end

  @doc """
  Validates the given partial changes (a map or keyword list) against the given entity type's declarations.
  Only present pairs are validated - absence is legal in a partial map, and a nil value is a violation only for a non-optional attribute or reference.
  Returns :ok, or {:error, violations} in the validate/1 shape, all violations accumulated.
  """
  @spec validate(module, %{atom => any} | keyword) ::
          :ok | {:error, %{atom => list(atom | {atom, any})}}
  def validate(entity_type, changes) do
    entity_type
    |> Validator.validate_changes(Map.new(changes))
    |> group_errors()
  end

  # A server-only attribute holds its sentinel in a struct on its way to the client - the page
  # context and a from_query prop both carry one - so the field admits it beside the declared type.
  defp attribute_field_type_ast(type, opts) do
    sentinel_types =
      if opts[:server_only] == true do
        [remote_type_ast(Entity.ServerOnly)]
      else
        []
      end

    union_types = Enum.concat([attribute_type_asts(type, opts), sentinel_types, [nil]])

    type_union(union_types)
  end

  # The Elixir types an attribute's field holds, from the type its declaration names. A uuid is a
  # string here - the canonical id format is a declaration check, not something a type can state.
  # An enum answers with its values rather than with a union of them, so that the field's own
  # union stays flat: a nested one is equivalent but renders as ":x | :y | nil" wrapped in
  # parentheses, and this type is what ExDoc shows on every entity's page.
  defp attribute_type_asts(:boolean, _opts), do: [quote(do: boolean())]
  defp attribute_type_asts(:date, _opts), do: [remote_type_ast(Date)]
  defp attribute_type_asts(:datetime, _opts), do: [remote_type_ast(DateTime)]
  defp attribute_type_asts(:enum, opts), do: Keyword.fetch!(opts, :values)
  defp attribute_type_asts(:float, _opts), do: [quote(do: float())]
  defp attribute_type_asts(:integer, _opts), do: [quote(do: integer())]
  defp attribute_type_asts(:string, _opts), do: [remote_type_ast(String)]
  defp attribute_type_asts(:time, _opts), do: [remote_type_ast(Time)]
  defp attribute_type_asts(:uuid, _opts), do: [remote_type_ast(Entity, :id)]

  # Reverse-expansion fixpoint - each pass admits the roles extending anything already admitted,
  # so a role reaching the given one through any number of hops ends up in the result.
  defp expand_role_names(names, extends_by_name) do
    expanded =
      Enum.reduce(extends_by_name, names, fn {name, targets}, acc ->
        if Enum.any?(targets, &MapSet.member?(names, &1)) do
          MapSet.put(acc, name)
        else
          acc
        end
      end)

    if MapSet.size(expanded) == MapSet.size(names) do
      Enum.sort(expanded)
    else
      expand_role_names(expanded, extends_by_name)
    end
  end

  defp field_type_asts(module) do
    attribute_field_types =
      module
      |> Module.get_attribute(:__attributes__)
      |> Enum.map(fn {name, type, opts} -> {name, attribute_field_type_ast(type, opts)} end)

    relationship_field_types =
      module
      |> Module.get_attribute(:__relationships__)
      |> Enum.flat_map(&relationship_field_type_asts/1)

    inverse_field_types =
      module
      |> Module.get_attribute(:__inverse_relationships__)
      |> Enum.map(&inverse_field_type_ast/1)

    system_attribute_field_types =
      Enum.map(@system_attributes, fn {name, type, opts} ->
        {name, attribute_field_type_ast(type, opts)}
      end)

    [
      {:__meta__, remote_type_ast(Entity.Metadata)}
      | Enum.concat([
          attribute_field_types,
          relationship_field_types,
          inverse_field_types,
          system_attribute_field_types
        ])
    ]
  end

  defp group_errors(:ok), do: :ok

  defp group_errors({:error, errors}) do
    grouped =
      Enum.group_by(errors, fn {name, _reason} -> name end, fn {_name, reason} -> reason end)

    {:error, grouped}
  end

  # An inverse holds its sentinel when not included, and once included a list of the related type's
  # structs for a set, one struct or nil for a single one.
  defp inverse_field_type_ast({name, [target], _opts}) do
    {name,
     type_union([{:list, [], [remote_type_ast(target)]}, remote_type_ast(Entity.NotIncluded)])}
  end

  defp inverse_field_type_ast({name, target, _opts}) do
    {name, type_union([remote_type_ast(target), remote_type_ast(Entity.NotIncluded), nil])}
  end

  # The reflection of the relationships kept apart from the stored ones - the inverses and where each
  # relationship was declared - generated beside the rest of __before_compile__, in a quote of its
  # own so the one __before_compile__ builds stays within the complexity the project's linter
  # allows.
  defp relationship_reflection do
    quote do
      @doc """
      Returns the list of inverse relationship definitions for the compiled entity type, sorted by relationship name - relationships declared with the inverse option, which store nothing of their own and read the relationship they reverse on the related type.
      """
      @spec __inverse_relationships__() :: list({atom, module | list(module), keyword})
      def __inverse_relationships__, do: Enum.sort(@__inverse_relationships__)

      @doc false
      @spec __relationship_locations__() :: %{atom => {String.t(), pos_integer}}
      def __relationship_locations__, do: Map.new(@__relationship_locations__)
    end
  end

  # Spelled with the module ATOM rather than with an alias, so that an entity module's own
  # aliases cannot redirect the name.
  defp remote_type_ast(module, name \\ :t), do: {{:., [], [module, name]}, [], []}

  # A to-many holds its sentinel until a query includes it and a list of the target's structs
  # after. A to-one splits into a reference field and an embed, and the embed admits nil whether
  # or not the reference is optional - a struct built by hand can carry one.
  defp relationship_field_type_asts({name, [target], _opts}) do
    union_types = [{:list, [], [remote_type_ast(target)]}, remote_type_ast(Entity.NotIncluded)]

    [{name, type_union(union_types)}]
  end

  defp relationship_field_type_asts({name, target, _opts}) do
    union_types = [remote_type_ast(target), remote_type_ast(Entity.NotIncluded), nil]

    # The reference field's atom is created by struct_fields/1, called just above in
    # __before_compile__ - this only has to find it.
    reference_name = String.to_existing_atom("#{name}_id")

    [
      {reference_name, type_union([remote_type_ast(Entity, :id), nil])},
      {name, type_union(union_types)}
    ]
  end

  # Walks the list cell by cell rather than through Enum, which raises on an improper list: one
  # whose last tail is not an empty list. Such a tail is stripped like any other term, and whoever
  # writes the list out decides whether it can carry one.
  defp strip_server_only_deep_list([head | tail]) do
    [strip_server_only_deep(head) | strip_server_only_deep_list(tail)]
  end

  defp strip_server_only_deep_list([]), do: []

  defp strip_server_only_deep_list(tail), do: strip_server_only_deep(tail)

  # A type is AST, not data: the field types name other modules' t/0, and those names have to
  # arrive in the entity's module unexpanded - which is why this is built rather than escaped.
  defp struct_type(module) do
    fields =
      module
      |> field_type_asts()
      |> Enum.sort()

    {:%, [], [{:__MODULE__, [], nil}, {:%{}, [], fields}]}
  end

  defp type_union(asts) do
    asts
    |> Enum.reverse()
    |> Enum.reduce(fn ast, acc -> {:|, [], [ast, acc]} end)
  end

  defp user_entity_marker(opts) do
    if Keyword.get(opts, :user) == true do
      [
        quote do
          @doc """
          Returns true to indicate that the callee module is the project's user entity type module (has "use Hologram.Entity, user: true" directive).

          ## Examples

              iex> __is_hologram_user_entity__()
              true
          """
          @spec __is_hologram_user_entity__() :: boolean
          def __is_hologram_user_entity__, do: true
        end
      ]
    else
      []
    end
  end

  defp validate_construction_values!(entity_type, values_map) do
    assigned_inverse_name =
      entity_type.__inverse_relationships__()
      |> Enum.map(fn {name, _type, _opts} -> name end)
      |> Enum.find(&Map.has_key?(values_map, &1))

    if assigned_inverse_name do
      raise ArgumentError,
        message:
          "relationship #{inspect(assigned_inverse_name)} of #{inspect(entity_type)} cannot be assigned at construction - it is an inverse that reads #{describe_inverse(entity_type, assigned_inverse_name)}, so write that instead"
    end

    assigned_relationship_name =
      entity_type.__relationships__()
      |> Enum.map(fn {name, _type, _opts} -> name end)
      |> Enum.find(&Map.has_key?(values_map, &1))

    if assigned_relationship_name do
      raise ArgumentError,
        message:
          "relationship #{inspect(assigned_relationship_name)} of #{inspect(entity_type)} cannot be assigned at construction - set a to-one reference via the :#{assigned_relationship_name}_id field, to-many edges via add_relationship"
    end

    validate_framework_values!(entity_type, values_map)

    :ok
  end

  # A job is enqueued as queued, by whoever is acting, and what happens to it afterwards is the
  # worker's to record - so the three attributes carrying that are refused here rather than
  # silently overwritten at the write.
  defp validate_framework_values!(entity_type, values_map) do
    framework_name =
      if Reflection.job?(entity_type) do
        Enum.find(Job.framework_attribute_names(), &Map.has_key?(values_map, &1))
      end

    if framework_name do
      raise ArgumentError,
        message:
          "#{inspect(framework_name)} of #{inspect(entity_type)} is set by the framework - a job is enqueued as queued, and the worker records the rest"
    end

    :ok
  end

  defp validated_field_names(entity_type) do
    attribute_names = Enum.map(entity_type.__attributes__(), fn {name, _type, _opts} -> name end)

    reference_names =
      entity_type.__relationships__()
      |> Enum.reject(fn {_name, type, _opts} -> is_list(type) end)
      |> Enum.map(fn {name, _type, _opts} -> String.to_existing_atom("#{name}_id") end)

    attribute_names ++ reference_names
  end
end
