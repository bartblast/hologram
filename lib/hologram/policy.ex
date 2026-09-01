defmodule Hologram.Policy do
  @moduledoc """
  The construct for policies shared by several entity types.

  `use Hologram.Policy` defines a policy module, which holds `role` and `allow` declarations
  written exactly as they are written inside an entity type:

      defmodule MyApp.Policies.AdminManaged do
        use Hologram.Policy

        alias MyApp.Roles.Admin

        allow :read, to: Admin
        allow :update, to: Admin
        allow :delete, to: Admin
      end

  `policy Mod` takes one on, and the taking module keeps declaring its own alongside:

      defmodule MyApp.Invoice do
        use Hologram.Entity

        attribute :number, :string

        policy MyApp.Policies.AdminManaged

        role :admin
        allow :grant_role, to: :admin
        allow :revoke_role, to: :admin
      end

  The canonical order inside an entity type is attributes, relationships, `policy` lines, roles,
  allows. Policy modules compose with the same line - one may take another, to any depth - and an
  entity type taking on the outer one receives the declarations of both.

  A role name is one role, however many places declare it. Every declaration adds to it: `extends`
  targets union, and `granted_to` follows the last declaration that mentions it, a declaration
  omitting the option having no opinion. So a policy can carry a role's extension while the entity
  type adds the creator grant, without either repeating the other:

      # in the policy
      role :owner, extends: :editor

      # in the entity type
      role :owner, granted_to: :creator

      # the entity type's __roles__/0
      [owner: [extends: [:editor], granted_to: :creator]]

  Rules accumulate the same way and are OR'd, so the order of `allow` lines carries no meaning.

  Declarations are evaluated where they are written, so aliases, module attributes and helper
  functions in a policy module mean what they mean there - the taking module receives values,
  not code to re-resolve.
  """

  alias Hologram.Auth.RoleGrant
  alias Hologram.Commons.Types, as: T
  alias Hologram.Entity
  alias Hologram.Entity.Validator, as: EntityValidator
  alias Hologram.Query
  alias Hologram.Reflection

  @model_facts_key {__MODULE__, :model_facts}

  # The two gate operations whose rules are compiled per role
  @role_operations [:grant_role, :revoke_role]

  defmacro __using__(_opts) do
    quote do
      import Hologram.Policy, only: [allow: 1, allow: 2, policy: 1, role: 1, role: 2]

      @doc """
      Returns true to indicate that the callee module is a policy module (has "use Hologram.Policy" directive).

      ## Examples

          iex> __is_hologram_policy__()
          true
      """
      @spec __is_hologram_policy__() :: boolean
      def __is_hologram_policy__, do: true

      Module.register_attribute(__MODULE__, :__policy_declarations__, accumulate: true)
      Module.register_attribute(__MODULE__, :__policy_declaration_sources__, accumulate: true)

      @before_compile Hologram.Policy
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    declarations =
      env.module
      |> Module.get_attribute(:__policy_declarations__)
      |> Enum.reverse()

    declaration_sources =
      env.module
      |> Module.get_attribute(:__policy_declaration_sources__)
      |> Enum.reverse()

    quote do
      @doc """
      Returns the role and allow declarations of the callee policy module, in declaration order.
      A role declaration is a {:role, name, opts} tuple and an allow declaration is an {:allow, operation, spec} tuple.
      """
      @spec __declarations__() :: list(tuple)
      def __declarations__, do: unquote(Macro.escape(declarations))

      @doc false
      @spec __declaration_sources__() :: list(module)
      def __declaration_sources__, do: unquote(Macro.escape(declaration_sources))
    end
  end

  @doc false
  @spec __take__(module, module) :: :ok
  def __take__(module, policy_module) do
    validate_policy_module!(module, policy_module)

    policy_module.__declarations__()
    |> Enum.zip(policy_module.__declaration_sources__())
    |> Enum.each(fn {declaration, source} -> replay(module, declaration, source) end)
  end

  @doc """
  Accumulates the given policy declaration, for replay into the entity types taking this policy on.

  Takes the same operation and spec as `Hologram.Entity.allow/2`.
  """
  @spec allow(atom, T.opts()) :: Macro.t()
  defmacro allow(operation, spec \\ []) do
    spec = Entity.replace_actor_leaves!(spec, __CALLER__.module)

    quote do
      operation = unquote(operation)
      spec = unquote(spec)

      EntityValidator.validate_allow!(__MODULE__, operation, spec)

      @__policy_declarations__ {:allow, operation, spec}
      @__policy_declaration_sources__ __MODULE__
    end
  end

  @doc """
  Takes on the roles and rules of the given policy module.

  Can be written in an entity type or in another policy module, to any depth. The declarations are
  copied in where the line is written, so they land in the taking module exactly as locally written
  ones do, and a role name declared on both sides is one role.
  """
  @spec policy(module) :: Macro.t()
  defmacro policy(module) do
    quote do
      # The require is load-bearing: it states a COMPILE-TIME dependency on the policy module,
      # which is what makes Elixir recompile this module when that policy changes. The
      # declarations are copied at compile time, so an out-of-date taker would silently carry
      # stale roles and rules. A bare alias passed as a function argument is only a runtime
      # reference, and an export dependency would not help either - a policy's declarations
      # change without its exported functions changing.
      require unquote(module)

      Hologram.Policy.__take__(__MODULE__, unquote(module))
    end
  end

  @doc """
  Accumulates the given role declaration, for replay into the entity types taking this policy on.

  Takes the same name and options as `Hologram.Entity.role/2`.
  """
  @spec role(atom, T.opts()) :: Macro.t()
  defmacro role(name, opts \\ []) do
    quote do
      name = unquote(name)
      opts = unquote(opts)

      EntityValidator.validate_role!(__MODULE__, name, opts)

      @__policy_declarations__ {:role, name, opts}
      @__policy_declaration_sources__ __MODULE__
    end
  end

  @doc """
  Builds the compiled policy of the given entity type: a map of operation to the list of rules granting it, in declaration order.

  The grant store's own policy is framework-supplied rather than declared: a user always sees
  the grants they hold, and sees others' grants on a resource when they hold one of that entity
  type's read-grants roles.

  A rule holds the predicate triples of its allow line, its grant references, and its delegation.
  Predicates carry the actor sentinel in value position where the declaration called user_id().
  Grant references are extends-expanded, so a reference to a role also names every role carrying it:
  own roles as {:own, role names}, another entity type's roles as {:type, entity type, role names},
  a related instance's roles as {:rel, relationship name, role names}, and global role modules as
  {:global, role modules} - nil when the line has none. The grant store's framework-supplied rules
  carry a fifth kind no declaration can spell, {:resource, entity type, role names}: roles held on
  the resource a grant row names.
  A rule grants its operation when its predicates hold, one of its grant references is held, and its
  delegation grants the same operation - and a policy grants its operation when any of its rules does.
  The grant lifecycle operations grant_role and revoke_role are compiled per role: a line naming a
  role, or a list of them, yields one {operation, role} key per role, and a bare line yields one per
  declared role its holders may cover - a holder's own role and every role it extends, so nobody is
  qualified above what they hold. The bare key is then the union of the per-role rules, answering
  whether the acting user may grant (or revoke) some role at all.
  """
  @spec build(module) :: %{
          Entity.operation() =>
            list(%{predicates: list(tuple), to: list(tuple) | nil, via: atom | nil})
        }
  def build(RoleGrant), do: %{read: role_grant_read_rules()}

  def build(entity_type) do
    entity_type.__policies__()
    |> Enum.map(fn {operation, to, via, predicates} ->
      rule = %{
        predicates: Query.predicate_triples!(entity_type, predicates),
        to: build_to(entity_type, to),
        via: via
      }

      {operation, rule}
    end)
    |> Enum.flat_map(&expand_role_operation(entity_type, &1))
    |> Enum.group_by(fn {operation, _rule} -> operation end, fn {_operation, rule} -> rule end)
    |> put_role_operation_unions()
  end

  @doc """
  Returns the given entity type modules that declare no allow lines, sorted.

  Such an entity type is statically dead under default deny - every query against it returns
  nothing, whatever the acting user holds. The grant store is never listed: its policy is
  framework-supplied rather than declared.
  """
  @spec dead_entity_types(list(module)) :: list(module)
  def dead_entity_types(entity_types) do
    entity_types
    |> Enum.filter(&(&1 != RoleGrant and &1.__policies__() == []))
    |> Enum.sort_by(&inspect/1)
  end

  @doc """
  Returns the own roles qualifying their holders to grant some role on the given entity type, sorted.

  These are the extends-expanded own roles across its allow :grant_role rules - empty when the entity
  type declares none, which leaves granting on it to the trusted tier.
  """
  @spec grant_role_qualifying_roles(module) :: list(atom)
  def grant_role_qualifying_roles(entity_type) do
    own_role_names(entity_type, :grant_role)
  end

  @doc """
  Returns the own roles qualifying their holders to grant the given role on the given entity type, sorted.

  These are the extends-expanded own roles of its allow :grant_role rules covering that role - empty
  when no rule covers it.
  """
  @spec grant_role_qualifying_roles(module, atom) :: list(atom)
  def grant_role_qualifying_roles(entity_type, role_name) do
    own_role_names(entity_type, {:grant_role, role_name})
  end

  @doc """
  Returns the key the given policy operation is baked under for the client: an atom as its name, and a per-role grant lifecycle operation as the two names joined by a colon, which no role name can contain.

  The client builds the same key in operationKey in assets/js/elixir/hologram/auth.mjs - a hand-ported pair, so a change here is a change there.
  """
  @spec operation_key(Entity.operation()) :: String.t()
  def operation_key(operation) when is_atom(operation), do: Atom.to_string(operation)

  def operation_key({name, role_name}), do: "#{name}:#{role_name}"

  @doc """
  Returns the own roles whose holders see the grants others hold on the given entity type, sorted.

  These are the extends-expanded own roles of its allow :read_roles rules together with every role
  qualifying to grant or revoke on it - a declared line adds readers, so nobody can change a list
  they cannot see.
  """
  @spec read_roles_qualifying_roles(module) :: list(atom)
  def read_roles_qualifying_roles(entity_type) do
    [
      own_role_names(entity_type, :read_roles),
      grant_role_qualifying_roles(entity_type),
      revoke_role_qualifying_roles(entity_type)
    ]
    |> Enum.concat()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc false
  @spec reset_model_facts_cache() :: :ok
  def reset_model_facts_cache do
    :persistent_term.erase(@model_facts_key)

    :ok
  end

  @doc """
  Returns the own roles qualifying their holders to revoke some role on the given entity type, sorted.

  These are the extends-expanded own roles across its allow :revoke_role rules - empty when the
  entity type declares none, which leaves revoking on it to the trusted tier.
  """
  @spec revoke_role_qualifying_roles(module) :: list(atom)
  def revoke_role_qualifying_roles(entity_type) do
    own_role_names(entity_type, :revoke_role)
  end

  @doc """
  Returns the own roles qualifying their holders to revoke the given role on the given entity type, sorted.

  These are the extends-expanded own roles of its allow :revoke_role rules covering that role - empty
  when no rule covers it.
  """
  @spec revoke_role_qualifying_roles(module, atom) :: list(atom)
  def revoke_role_qualifying_roles(entity_type, role_name) do
    own_role_names(entity_type, {:revoke_role, role_name})
  end

  defp build_global_reference([]), do: []

  defp build_global_reference(role_modules) do
    expanded_modules =
      role_modules
      |> Enum.flat_map(&expand_global_role/1)
      |> Enum.uniq()
      |> Enum.sort()

    [{:global, expanded_modules}]
  end

  defp build_own_reference(_entity_type, []), do: []

  defp build_own_reference(entity_type, role_names) do
    expanded_names =
      role_names
      |> Enum.flat_map(&Entity.expand_role(entity_type, &1))
      |> Enum.uniq()
      |> Enum.sort()

    [{:own, expanded_names}]
  end

  defp build_to(_entity_type, nil), do: nil

  defp build_to(entity_type, to) do
    references = List.wrap(to)

    {role_modules, plain_references} = Enum.split_with(references, &Reflection.alias?/1)
    {role_names, typed_references} = Enum.split_with(plain_references, &is_atom/1)

    own_reference = build_own_reference(entity_type, role_names)
    typed = Enum.map(typed_references, &build_typed_reference(entity_type, &1))
    global_reference = build_global_reference(role_modules)

    own_reference ++ typed ++ global_reference
  end

  defp build_typed_reference(entity_type, {reference, role_name}) do
    if Reflection.alias?(reference) do
      {:type, reference, Entity.expand_role(reference, role_name)}
    else
      target_type = Entity.relationship_target(entity_type, reference)

      {:rel, reference, Entity.expand_role(target_type, role_name)}
    end
  end

  # A bare grant lifecycle line covers, for each declared role, the holders it names whose own
  # role is that role or extends it - so the rule for a role above what a holder holds names
  # nobody, and is not emitted. A line naming a list of roles is one rule per role, and one
  # naming a single role stands as written.
  defp expand_role_operation(entity_type, {operation, rule}) when operation in @role_operations do
    entity_type.__roles__()
    |> Enum.map(fn {role_name, _opts} ->
      holders =
        rule
        |> own_reference_names()
        |> Enum.filter(&(&1 in Entity.expand_role(entity_type, role_name)))

      {role_name, holders}
    end)
    |> Enum.reject(fn {_role_name, holders} -> holders == [] end)
    |> Enum.map(fn {role_name, holders} ->
      {{operation, role_name}, %{rule | to: [{:own, holders}]}}
    end)
  end

  defp expand_role_operation(_entity_type, {{operation, role_names}, rule})
       when operation in @role_operations and is_list(role_names) do
    Enum.map(role_names, &{{operation, &1}, rule})
  end

  defp expand_role_operation(_entity_type, {operation, rule}), do: [{operation, rule}]

  # A reference to a role module is satisfied by every role carrying it - the module itself and
  # every role whose extends chain reaches it. The sweep is model-wide: role modules resolve
  # globally, so a reference means the same thing in every entity type.
  defp expand_global_role(role_module) do
    expand_global_role_modules(MapSet.new([role_module]), model_facts().extends_by_role_module)
  end

  defp expand_global_role_modules(modules, extends_by_module) do
    expanded =
      Enum.reduce(extends_by_module, modules, fn {module, targets}, acc ->
        if Enum.any?(targets, &MapSet.member?(modules, &1)) do
          MapSet.put(acc, module)
        else
          acc
        end
      end)

    if MapSet.size(expanded) == MapSet.size(modules) do
      Enum.sort(expanded)
    else
      expand_global_role_modules(expanded, extends_by_module)
    end
  end

  # Both facts are model-wide sweeps over every module in the project, and policies are built
  # on the request path - per policied query, per delegation hop and per can? call - so they are
  # computed once and cached for the lifetime of the runtime, like the physical name mapping.
  # The compiler and the application boot reset the cache, so a recompiled model is picked up.
  defp model_facts do
    case :persistent_term.get(@model_facts_key, nil) do
      nil ->
        facts = %{
          entity_types: Reflection.list_entities(),
          extends_by_role_module:
            Map.new(Reflection.list_roles(), fn module -> {module, module.__extends__()} end)
        }

        :persistent_term.put(@model_facts_key, facts)

        facts

      facts ->
        facts
    end
  end

  defp own_reference_names(%{to: nil}), do: []

  defp own_reference_names(%{to: references}) do
    Enum.flat_map(references, fn
      {:own, role_names} -> role_names
      _other_reference -> []
    end)
  end

  defp own_role_names(entity_type, operation) do
    entity_type
    |> build()
    |> Map.get(operation, [])
    |> Enum.flat_map(&own_reference_names/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # The bare key answers whether the acting user may grant (or revoke) some role: every per-role
  # rule, in role order. A bare line's own rule is not kept - the per-role rules it expanded to
  # are its meaning, and their union says the same about "some role" as the line did.
  defp put_role_operation_unions(rules_by_operation) do
    Enum.reduce(@role_operations, rules_by_operation, fn operation, acc ->
      union =
        acc
        |> Enum.filter(fn
          {{^operation, _role_name}, _rules} -> true
          _other -> false
        end)
        |> Enum.sort()
        |> Enum.flat_map(fn {_key, rules} -> rules end)

      if union == [] do
        Map.delete(acc, operation)
      else
        Map.put(acc, operation, union)
      end
    end)
  end

  # Everyone sees the grants they hold. Seeing someone else's grants on a resource takes one of
  # that resource type's read-grants roles, held on the very resource the grant row names - so
  # the check reads grant rows through grant rows, never through this policy again.
  # The source travels with the declaration rather than being recomputed here: a line taken
  # through several policies names the module whose BODY wrote it, not the last hop it came by.
  defp replay(module, declaration, source) do
    if Module.has_attribute?(module, :__policies__) do
      replay_into_entity(module, declaration, source)
    else
      Module.put_attribute(module, :__policy_declarations__, declaration)
      Module.put_attribute(module, :__policy_declaration_sources__, source)
    end
  end

  defp replay_into_entity(module, {:allow, operation, spec}, source) do
    Entity.__put_policy__(module, operation, spec, source)
  end

  defp replay_into_entity(module, {:role, name, opts}, source) do
    Entity.__put_role__(module, name, opts, source)
  end

  defp role_grant_read_rules do
    resource_rules =
      model_facts().entity_types
      |> Enum.reject(&(&1 == RoleGrant))
      |> Enum.map(&{&1, read_roles_qualifying_roles(&1)})
      |> Enum.reject(fn {_entity_type, role_names} -> role_names == [] end)
      |> Enum.sort_by(fn {entity_type, _role_names} -> RoleGrant.resource_type(entity_type) end)
      |> Enum.map(&role_grant_resource_rule/1)

    [%{predicates: [{:user_id, :==, {:actor}}], to: nil, via: nil} | resource_rules]
  end

  defp role_grant_resource_rule({entity_type, role_names}) do
    %{
      predicates: [{:resource_type, :==, RoleGrant.resource_type(entity_type)}],
      to: [{:resource, entity_type, role_names}],
      via: nil
    }
  end

  defp validate_policy_module!(module, policy_module) do
    if not Reflection.policy?(policy_module) do
      raise Hologram.CompileError,
        message:
          "invalid policy #{inspect(policy_module)} taken in #{inspect(module)} - #{inspect(policy_module)} is not a policy module (define it with use Hologram.Policy)"
    end
  end
end
