defmodule Hologram.Entity do
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.AST
  alias Hologram.Entity
  alias Hologram.Entity.NotIncluded
  alias Hologram.Entity.ServerOnly
  alias Hologram.Entity.Validator
  alias Hologram.Job
  alias Hologram.Reflection

  @system_attributes [
    {:created_at, :datetime, []},
    {:id, :uuid, []},
    {:updated_at, :datetime, []}
  ]

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
      end,
      register_attributes_accumulator(),
      register_policies_accumulator(),
      register_policy_sources_accumulator(),
      register_role_declarations_accumulator(),
      register_relationships_accumulator(),
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

    quote do
      # The metadata struct is expanded HERE, in the entity's own module body, so the module
      # carries a compile-time dependency on it. Escaping a pre-built one instead bakes a copy of
      # whatever shape it had when the FRAMEWORK compiled, and an incremental build never
      # revisits it: a field added to the metadata would leave every entity holding the old
      # shape, disagreeing with a freshly constructed one for as long as the build lasts.
      defstruct Enum.sort([
                  {:__meta__, %Hologram.Entity.Metadata{}} | unquote(struct_fields)
                ])

      @doc """
      Returns the list of attribute definitions for the compiled entity type, sorted by attribute name.
      """
      @spec __attributes__() :: list({atom, atom, keyword})
      def __attributes__, do: Enum.sort(@__attributes__)

      @doc """
      Returns the list of policy definitions for the compiled entity type, in declaration order.
      Policy rules are OR'd, so the order carries no semantics - it is preserved to keep reflection output readable against the source.
      """
      @spec __policies__() :: list({atom, term, atom | nil, keyword})
      def __policies__, do: Enum.reverse(@__policies__)

      @doc false
      @spec __policy_sources__() :: list(module)
      def __policy_sources__, do: Enum.reverse(@__policy_sources__)

      @doc """
      Returns the list of relationship definitions for the compiled entity type, sorted by relationship name.
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
    end
  end

  @doc """
  Accumulates the given policy definition in __policies__ module attribute.
  A policy line grants the given operation when its predicates hold and its grant reference (the to option) or delegation (the via option) is satisfied - a line with no options grants the operation unconditionally.
  A `user_id()` call in a predicate value position stands for the acting user's entity id and is stored as the actor sentinel.
  """
  @spec allow(atom, T.opts()) :: Macro.t()
  defmacro allow(operation, spec \\ []) do
    spec = replace_actor_leaves!(spec, __CALLER__.module)

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
  Accumulates the given relationship definition in __relationships__ module attribute.
  A relationship is to-one when its type is a module and to-many when its type is a one-element list wrapping a module.
  """
  @spec relationship(atom, module | list(module), T.opts()) :: Macro.t()
  defmacro relationship(name, type, opts \\ []) do
    quote do
      name = unquote(name)
      type = unquote(type)
      opts = unquote(opts)

      Validator.validate_relationship!(__MODULE__, name, type, opts)
      Module.put_attribute(__MODULE__, :__relationships__, {name, type, opts})
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
  @spec generate_id() :: String.t()
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
  """
  @spec new(module, %{optional(atom) => any} | keyword) :: struct
  def new(entity_type, values \\ %{}) do
    values_map = Map.new(values)

    Validator.validate_writable!(entity_type)
    validate_construction_values!(entity_type, values_map)

    declared_defaults =
      entity_type.__attributes__()
      |> Enum.filter(fn {_name, _type, opts} -> Keyword.has_key?(opts, :default) end)
      |> Map.new(fn {name, _type, opts} -> {name, Keyword.fetch!(opts, :default)} end)

    fields =
      declared_defaults
      |> Map.put(:id, generate_id())
      |> Map.merge(values_map)

    struct!(entity_type, fields)
  end

  @doc false
  @spec __put_policy__(module, atom, T.opts(), module) :: :ok
  def __put_policy__(module, operation, spec, source) do
    Validator.validate_allow!(module, operation, spec)

    policy =
      {operation, Keyword.get(spec, :to), Keyword.get(spec, :via),
       Keyword.drop(spec, [:to, :via])}

    Module.put_attribute(module, :__policies__, policy)
    Module.put_attribute(module, :__policy_sources__, source)

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

  @doc false
  @spec register_attributes_accumulator() :: AST.t()
  def register_attributes_accumulator do
    quote do
      Module.register_attribute(__MODULE__, :__attributes__, accumulate: true)
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

  # The replacement happens on the AST, before the spec is evaluated in the module body -
  # a real user_id() call would be an undefined function there. Policies have no variable
  # scope, so a paren-less user_id can only be the call written without its parens.
  @doc false
  @spec replace_actor_leaves!(Macro.t(), module) :: Macro.t()
  def replace_actor_leaves!(spec, module) do
    Macro.prewalk(spec, fn
      {:user_id, _meta, []} ->
        Macro.escape({:actor})

      {:user_id, _meta, context} when is_atom(context) ->
        raise Hologram.CompileError,
          message:
            "paren-less user_id in a policy in #{inspect(module)} - did you mean user_id()?"

      node ->
        node
    end)
  end

  @doc false
  @spec server_only_attribute_names(module) :: list(atom)
  def server_only_attribute_names(entity_type) do
    entity_type.__attributes__()
    |> Enum.filter(fn {_name, _type, opts} -> opts[:server_only] == true end)
    |> Enum.map(fn {name, _type, _opts} -> name end)
  end

  @doc false
  @spec strip_server_only(struct) :: struct
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
    Enum.map(term, &strip_server_only_deep/1)
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
  @doc false
  # sobelow_skip ["DOS.BinToAtom"]
  @spec struct_fields(module) :: list({atom, any})
  def struct_fields(module) do
    system_attribute_fields =
      Enum.map(@system_attributes, fn {name, _type, _opts} -> {name, nil} end)

    attribute_fields =
      module
      |> Module.get_attribute(:__attributes__)
      |> Enum.map(fn {name, _type, _opts} -> {name, nil} end)

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

    Enum.sort(system_attribute_fields ++ attribute_fields ++ relationship_fields)
  end

  @doc """
  Validates the given entity struct against its entity type's declarations - attribute types, enum values, required presence, the declared constraint options, and to-one references (required presence, canonical entity id format).
  Returns :ok, or {:error, violations} where violations maps each violating field name to the list of its violation reasons, all violations accumulated.
  """
  @spec validate(struct) :: :ok | {:error, %{atom => list(atom | {atom, any})}}
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

  defp group_errors(:ok), do: :ok

  defp group_errors({:error, errors}) do
    grouped =
      Enum.group_by(errors, fn {name, _reason} -> name end, fn {_name, reason} -> reason end)

    {:error, grouped}
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
