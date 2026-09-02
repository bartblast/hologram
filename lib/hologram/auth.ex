defmodule Hologram.Auth do
  @moduledoc false

  alias Hologram.Auth.Context
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Mapper
  alias Hologram.DB.Outbox
  alias Hologram.DB.QueryRunner
  alias Hologram.Entity
  alias Hologram.Entity.Validator
  alias Hologram.Policy
  alias Hologram.Policy.Evaluator
  alias Hologram.Query
  alias Hologram.Query.Window
  alias Hologram.Reflection
  alias Hologram.Sync.Carry

  @doc """
  Returns the window a client checking permissions locally downloads: every grant row, narrowed
  per client by the policy the read path applies - each client receives its own grants plus the
  ones it may administer, and nothing else.

  Derived here rather than in either caller so that the build (which decides which pages
  subscribe to it) and the query cache (which resolves the id back to a term) name one window
  and not two.
  """
  @spec grants_window() :: Query.t()
  def grants_window do
    RoleGrant
    |> Query.normalize()
    |> Window.derive()
  end

  @doc """
  Returns the grant rows answering the permission checks a render ran - the rows the given
  {user id, scope} pairs ask about, read as the session user.

  What a check asks is whether a grant EXISTS, so nothing it reads can be gathered. The questions
  are gathered instead, and answered here in one query per distinct user and resource type: a
  page checking a hundred rows of one type asks once, with the ids as a membership list.

  Read through the policied path, as the fill is - so a row travels only when the session user
  may hold it. A template checking ANOTHER user's access carries that user's row exactly when
  the session user's own read rules admit it.
  """
  @spec carried_grants(MapSet.t({String.t() | nil, tuple | atom})) :: list(struct)
  def carried_grants(scopes) do
    session_user_id = user_id()

    if session_user_id && MapSet.size(scopes) > 0 do
      scopes
      |> grant_scope_groups()
      |> Enum.flat_map(&grant_group_rows(&1, session_user_id))
      |> Enum.uniq_by(& &1.id)
    else
      []
    end
  end

  @doc """
  Returns true when the given user may perform the given operation on the given entity, or false otherwise.

  Takes the user entity or a bare user id, and nil for an anonymous session - rules referencing
  the acting user never match then. An operation the entity type declares no rule for is denied.

  The operation is an atom, or `{:grant_role, role}` / `{:revoke_role, role}` asking about one role -
  the bare `:grant_role` or `:revoke_role` asks whether the user may grant or revoke some role at all.
  A tuple naming several roles raises: can? asks about one role at a time.
  """
  @spec can?(struct | String.t() | nil, atom | {atom, atom}, struct) :: boolean
  def can?(user_or_id, operation, entity) do
    evaluate(user_or_id, operation, entity, :stored)
  end

  # The same evaluation against grants the caller supplies rather than the ones the store holds,
  # for asking what a user COULD have seen under a set of grants that is not the current one.
  # Every rule kind is answered from the list, delegations included - a rule that fell back to
  # the store would judge half the policy under grants the caller did not ask about.
  @doc false
  @spec can?(struct | String.t() | nil, atom | {atom, atom}, struct, list(struct)) :: boolean
  def can?(user_or_id, operation, entity, grants) do
    evaluate(user_or_id, operation, entity, grants)
  end

  # The id of the row a chain of to-one relationships ends at, or nil when any hop along the way
  # is empty. The intermediate rows are read raw, the way `check_requirement({:via, _}, ...)`
  # reads a delegation target: what is being asked is where the chain LEADS, and a read that
  # applied the intermediate row's own rules would answer nil for a chain the policy follows.
  #
  # A hop naming a row that is gone answers nil the same way an empty reference does - a chain
  # that leads nowhere leads nowhere, however it got there.
  @doc false
  @spec chain_target_id(struct, list(atom)) :: Entity.id() | nil
  def chain_target_id(entity, [relationship_name]) do
    related_id(entity, relationship_name)
  end

  def chain_target_id(entity, [relationship_name | rest]) do
    case related_id(entity, relationship_name) do
      nil ->
        nil

      target_id ->
        entity.__struct__
        |> relationship_target(relationship_name)
        |> EntityOperations.get(target_id)
        |> chain_target_id_or_nil(rest)
    end
  end

  # The grants the given user held before the given grant effects were written - what a resuming
  # client's rules were answered against at the place it is coming back from: the grants it holds
  # NOW, with everything the log says has happened to them since taken back off.
  #
  # Undone from the present BACKWARDS, which is what makes a grant given and taken back inside the
  # run answer correctly - forwards, its creation would be undone before its deletion put it back,
  # leaving a grant the user never held. Grant rows are only ever created and deleted, never
  # patched, so undoing one is adding or removing a whole row and the order is the only subtlety.
  #
  # A deleted grant is rebuilt from what its effect recorded, which is why a delete carries the
  # row it removed.
  @doc false
  @spec grants_before(String.t(), list(map)) :: list(struct)
  def grants_before(user_id, grant_effects) do
    current =
      RoleGrant
      |> Query.filter(user_id: user_id)
      |> Query.normalize()
      |> QueryRunner.run(DB.mapping())

    grant_effects
    |> Enum.reverse()
    |> Enum.reduce(current, &undo_grant_effect/2)
  end

  @doc """
  Grants the given global role to the given user and returns :ok.

  Takes the user entity or a bare user id. The role is a module defined with use Hologram.Role -
  a global role is held without a resource, so it applies everywhere.
  Granting a role the user already holds keeps the original grant, metadata included.

  Trusted-only: raises when an acting user is set, since no role qualifies its holder to hand
  out powers that span the whole app.
  """
  @spec grant_role(struct | String.t(), module) :: :ok
  def grant_role(user_or_id, role) do
    user_id = validate_user_id!(user_or_id)

    validate_global_role!(role)
    authorize_trusted_write!("global", "granted")

    write_grant(user_id, nil, nil, role)
  end

  @doc """
  Grants the given role on the given resource to the given user and returns :ok.

  Takes the user entity or a bare user id. An entity struct grants the role on that row, an
  entity type module grants it on every row of the type. The role must be declared on the
  resource's entity type. Granting a role the user already holds on the same resource keeps
  the original grant, metadata included.

  An acting user must be allowed to grant the role by the resource type's allow :grant_role rules,
  the same answer can?/3 gives for {:grant_role, role} - by default their own role and every role
  it extends, so nobody hands out more than they hold, or a global role the line names. Trusted
  code running without an acting user grants whatever it needs, and a type-wide grant is
  trusted-only.
  """
  @spec grant_role(struct | String.t(), struct | module, atom) :: :ok
  def grant_role(user_or_id, resource, role) do
    user_id = validate_user_id!(user_or_id)
    {entity_type, resource_id} = resource_reference(resource)

    validate_declared_role!(entity_type, role)
    authorize_grant!(entity_type, resource_id, role)

    write_grant(user_id, RoleGrant.resource_type(entity_type), resource_id, role)
  end

  @doc false
  @spec apply_grant_write(RoleGrant.t(), String.t() | nil) :: :created | :present
  # grant_role/3's twin for a grant made in a browser: the same gate, asked about the actor the
  # request authenticated rather than about anything the batch carried.
  #
  # Where the verb reads an absent actor as trusted code, this reads it as an anonymous session -
  # a client is never the trusted tier, so both shapes trusted code writes are refused outright and
  # nobody signed in grants nothing. The row is already built and its granter already overwritten
  # by Hologram.Mutation.Write.to_entity/1, so what is left is the gate and the insert.
  def apply_grant_write(%RoleGrant{resource_id: nil} = grant, _actor_user_id) do
    raise Hologram.AccessDeniedError, trusted_write_message(trusted_scope(grant), "granted")
  end

  def apply_grant_write(%RoleGrant{}, nil) do
    raise Hologram.AccessDeniedError, signed_in_write_message("granted")
  end

  def apply_grant_write(%RoleGrant{} = grant, actor_user_id) do
    entity_type = RoleGrant.entity_type(grant.resource_type)

    check_grant!(gate_resource(entity_type, grant.resource_id), grant.role, actor_user_id)

    EntityOperations.create_if_absent(grant)
  end

  @doc """
  Revokes the given global role from the given user and returns :ok.

  Takes the user entity or a bare user id. The role is a module defined with use Hologram.Role.
  Revoking a role the user does not hold is a no-op.

  Trusted-only: raises when an acting user is set, as its granting counterpart does.
  """
  @spec revoke_role(struct | String.t(), module) :: :ok
  def revoke_role(user_or_id, role) do
    user_id = validate_user_id!(user_or_id)

    validate_global_role!(role)
    authorize_trusted_write!("global", "revoked")

    delete_grant(user_id, nil, nil, role)
  end

  @doc """
  Revokes the given role on the given resource from the given user and returns :ok.

  Takes the user entity or a bare user id, and an entity struct or entity type module for
  the resource. Revoking a role the user does not hold is a no-op.

  Under an acting user: revoking one's own role is always allowed, which is how a member leaves
  a resource - revoking someone else's requires being allowed to revoke that role by the resource
  type's allow :revoke_role rules, the same answer can?/3 gives for {:revoke_role, role} - and the
  last own role qualifying to grant on a resource can't be revoked, so a resource never loses its
  last manager while its members administer it.
  Trusted code running without an acting user is subject to neither, and is how a resource's
  roles are set up and torn down. A type-wide revocation is trusted-only.
  """
  @spec revoke_role(struct | String.t(), struct | module, atom) :: :ok
  def revoke_role(user_or_id, resource, role) do
    user_id = validate_user_id!(user_or_id)
    {entity_type, resource_id} = resource_reference(resource)

    validate_declared_role!(entity_type, role)

    # The last-manager guard counts the managing grants and then deletes one, so the two
    # statements run in a transaction with the counted rows locked - concurrent revokes of a
    # resource's final managing roles would otherwise both see a survivor and both delete.
    {:ok, :ok} =
      Connection.transaction(fn ->
        authorize_revoke!(entity_type, resource_id, user_id, role)

        delete_grant(user_id, RoleGrant.resource_type(entity_type), resource_id, role)
      end)

    :ok
  end

  @doc false
  @spec apply_revocation_write(RoleGrant.t(), String.t() | nil) :: :ok
  # revoke_role/3's twin for a revocation made in a browser: the same two gates, asked about the
  # actor the request authenticated rather than about anything the batch carried.
  #
  # Where the verb reads an absent actor as trusted code, this reads it as an anonymous session -
  # a client is never the trusted tier, so both shapes trusted code writes are refused outright and
  # nobody signed in revokes nothing. The row comes from the store rather than from the write, so
  # its columns are the ones the grant was made with, whatever the client believed it was deleting.
  #
  # Runs in the caller's transaction, which the last-manager guard needs - see check_revocation!/4.
  def apply_revocation_write(%RoleGrant{resource_id: nil} = grant, _actor_user_id) do
    raise Hologram.AccessDeniedError, trusted_write_message(trusted_scope(grant), "revoked")
  end

  def apply_revocation_write(%RoleGrant{}, nil) do
    raise Hologram.AccessDeniedError, signed_in_write_message("revoked")
  end

  def apply_revocation_write(%RoleGrant{} = grant, actor_user_id) do
    entity_type = RoleGrant.entity_type(grant.resource_type)
    resource = gate_resource(entity_type, grant.resource_id)

    check_revocation!(resource, grant.user_id, grant.role, actor_user_id)

    EntityOperations.delete(RoleGrant, grant.id)
  end

  @doc """
  Returns the entity id of the user the running work is authorized as, or nil when the
  session is anonymous. Framework wrappers set the actor around the work they run, so the
  value always comes from an authenticated session and never from anything a client sends.
  """
  @spec user_id() :: String.t() | nil
  defdelegate user_id, to: Context, as: :actor_user_id

  defp actor_user_id(%{id: id}), do: id

  defp actor_user_id(user_id), do: user_id

  # Granting on a resource is the per-role question can?/3 answers, asked of the evaluator with
  # an id-only struct: a gate line carries no predicate and no delegation (the policy validator
  # refuses both), so nothing but the id is ever read, and the button and the gate agree by
  # construction. Running with no actor is the trusted tier - scripts, consoles and seeds grant
  # whatever they need.
  defp authorize_grant!(_entity_type, nil, _role),
    do: authorize_trusted_write!("type-wide", "granted")

  defp authorize_grant!(entity_type, resource_id, role) do
    case Context.actor_user_id() do
      nil -> :ok
      actor_user_id -> check_grant!(gate_resource(entity_type, resource_id), role, actor_user_id)
    end
  end

  # Users may always revoke their own roles - leaving a resource needs no permission. Taking
  # a role from someone else is the per-role question can?/3 answers, and the last own role
  # qualifying to grant never goes, so a resource can never be left with nobody able to add
  # anyone - a global holder is not counted, since one leaving orphans nothing.
  defp authorize_revoke!(_entity_type, nil, _user_id, _role) do
    authorize_trusted_write!("type-wide", "revoked")
  end

  defp authorize_revoke!(entity_type, resource_id, user_id, role) do
    case Context.actor_user_id() do
      nil ->
        :ok

      actor_user_id ->
        check_revocation!(gate_resource(entity_type, resource_id), user_id, role, actor_user_id)
    end
  end

  defp authorize_trusted_write!(scope, verb) do
    if Context.actor_user_id() do
      raise Hologram.AccessDeniedError, trusted_write_message(scope, verb)
    end

    :ok
  end

  # The two gates a revocation passes, asked the same way by the verb and by a batch's revocation
  # write so the two cannot drift: dropping one's own role needs no permission, taking someone
  # else's is the per-role question, and the last role able to manage the resource never goes.
  #
  # Must run inside the caller's transaction - count_managing_grants/3 takes its rows FOR UPDATE,
  # which is what stops two concurrent revocations of a resource's final managing roles from each
  # seeing a survivor.
  defp check_revocation!(resource, user_id, role, actor_user_id) do
    entity_type = resource.__struct__

    if actor_user_id != user_id and not can?(actor_user_id, {:revoke_role, role}, resource) do
      raise Hologram.AccessDeniedError,
            unqualified_role_message(entity_type, resource.id, actor_user_id, role, :revoke_role)
    end

    granting_role_names = Policy.grant_role_qualifying_roles(entity_type)

    guard_last_managing_role!(entity_type, resource.id, role, granting_role_names)
  end

  # The gate a grant passes, asked the same way by the verb and by a batch's grant write so the two
  # cannot drift: whoever is acting must be allowed to grant this role on this row. A gate line
  # reads nothing of the row but its id, so an id-only struct is the whole resource it needs.
  defp check_grant!(resource, role, actor_user_id) do
    if not can?(actor_user_id, {:grant_role, role}, resource) do
      raise Hologram.AccessDeniedError,
            unqualified_role_message(
              resource.__struct__,
              resource.id,
              actor_user_id,
              role,
              :grant_role
            )
    end

    :ok
  end

  # Global roles are held without a resource - the grant shape leaving both resource columns nil.
  defp check_requirement({:global, role_modules}, _entity, actor_user_id, _operation, source) do
    grant_exists?(actor_user_id, :global, role_modules, source)
  end

  # Own roles are held on the entity itself or on its whole type - the two grant shapes the
  # store keeps apart by whether its resource_id column is nil.
  defp check_requirement({:own, role_names}, entity, actor_user_id, _operation, source) do
    grant_exists?(actor_user_id, {:own, entity.__struct__, entity.id}, role_names, source)
  end

  defp check_requirement(
         {:type, target_type, role_names},
         _entity,
         actor_user_id,
         _operation,
         source
       ) do
    grant_exists?(actor_user_id, {:type, target_type}, role_names, source)
  end

  defp check_requirement(
         {:rel, relationship_name, role_names},
         entity,
         actor_user_id,
         _operation,
         source
       ) do
    case related_id(entity, relationship_name) do
      nil ->
        false

      target_id ->
        target_type = relationship_target(entity.__struct__, relationship_name)

        grant_exists?(actor_user_id, {:instance, target_type, target_id}, role_names, source)
    end
  end

  # The grant store's own policy: a role held on the resource this grant row names.
  defp check_requirement(
         {:resource, target_type, role_names},
         entity,
         actor_user_id,
         _operation,
         source
       ) do
    case entity.resource_id do
      nil ->
        false

      resource_id ->
        grant_exists?(actor_user_id, {:instance, target_type, resource_id}, role_names, source)
    end
  end

  # Delegation asks the related entity's policy for the same operation. The related row is read
  # raw, because a policy that could not see its own delegation target would deny everything.
  defp check_requirement({:via, relationship_name}, entity, actor_user_id, operation, source) do
    case related_id(entity, relationship_name) do
      nil ->
        false

      target_id ->
        entity.__struct__
        |> relationship_target(relationship_name)
        |> EntityOperations.get(target_id)
        |> delegates?(actor_user_id, operation, source)
    end
  end

  defp chain_target_id_or_nil(nil, _chain), do: nil

  defp chain_target_id_or_nil(entity, chain), do: chain_target_id(entity, chain)

  # The rows are selected rather than counted in SQL because Postgres rejects FOR UPDATE with
  # aggregates - the lock is the point, and a resource's managing grants are few.
  # sobelow_skip ["SQL.Query"]
  defp count_managing_grants(entity_type, resource_id, role_names) do
    statement = """
    SELECT "id" FROM "hologram_data"."hologram_role_grant"
    WHERE "resource_type" = $1::#{qualified_enum_type("resource_type")}
      AND "resource_id" = $2
      AND "role" = ANY($3::#{qualified_enum_type("role")}[])
    FOR UPDATE
    """

    params = [
      resource_type_value(entity_type),
      Codec.encode(resource_id, :uuid),
      Enum.map(role_names, &Codec.encode(&1, :enum))
    ]

    {:ok, %{rows: rows}} = Connection.query(statement, params)

    length(rows)
  end

  defp delegates?(nil, _actor_user_id, _operation, _source), do: false

  defp delegates?(target, actor_user_id, operation, source) do
    evaluate(actor_user_id, operation, target, source)
  end

  # Nils encode the type-wide and global grant shapes, so the lookup matches them as values -
  # the same comparison the store's unique index makes, which is what identifies ONE grant and
  # why the row is not found by id. It is locked as it is found, so the delete that follows
  # removes the row this statement read rather than whatever stands there by then.
  #
  # Removing it through the delete verb rather than with a DELETE of its own is what records it:
  # one path records every deletion, and a grant row is spoken of on the stream exactly as any
  # other row is. A client watching its own grants is told a row is gone by the round the effect
  # wakes, so a revocation nothing records is a revocation no client hears about until it renders
  # afresh. Revoking a role the user does not hold finds no rows and records nothing.
  # sobelow_skip ["SQL.Query"]
  defp delete_grant(user_id, resource_type, resource_id, role) do
    statement = """
    SELECT "id" FROM "hologram_data"."hologram_role_grant"
    WHERE "user_id" = $1
      AND "resource_type" IS NOT DISTINCT FROM $2::#{qualified_enum_type("resource_type")}
      AND "resource_id" IS NOT DISTINCT FROM $3
      AND "role" = $4::#{qualified_enum_type("role")}
    FOR UPDATE
    """

    params = [
      Codec.encode(user_id, :uuid),
      resource_type && Atom.to_string(resource_type),
      Codec.encode(resource_id, :uuid),
      Codec.encode(role, :enum)
    ]

    {:ok, :ok} =
      Connection.transaction(fn ->
        {:ok, %{rows: rows}} = Connection.query(statement, params)

        Enum.each(rows, fn [id] ->
          :ok = EntityOperations.delete(RoleGrant, Codec.decode(id, :uuid))
        end)
      end)

    :ok
  end

  # An own-scope check matches the row naming the resource AND the type-wide row, which is why
  # nil rides in the id list beside the ids - the store keeps the two apart by that column being
  # null, and a membership list holding nil compiles to "= ANY(...) OR IS NULL".
  # The DSL takes a list of roles as sugar for one line per role, so there is no rule keyed by a
  # list to answer - and "all of them" and "any of them" are each other's opposite, so neither is
  # chosen silently.
  defp evaluate(_user_or_id, {_name, role_names} = operation, _entity, _source)
       when is_list(role_names) do
    raise ArgumentError, "can? asks about one role - #{inspect(operation)} names several"
  end

  defp evaluate(user_or_id, operation, entity, source) do
    policy = Policy.build(entity.__struct__)
    checker = &check_requirement(&1, &2, &3, operation, source)

    Evaluator.grants?(policy, operation, entity, actor_user_id(user_or_id), checker)
  end

  defp grant_group_key({user_id, {:own, entity_type, _resource_id}}), do: {user_id, entity_type}

  defp grant_group_key({user_id, {:instance, entity_type, _resource_id}}),
    do: {user_id, entity_type}

  defp grant_group_key({user_id, {:type, entity_type}}), do: {user_id, entity_type}

  defp grant_group_key({user_id, :global}), do: {user_id, nil}

  defp grant_group_resource_ids({:own, _entity_type, resource_id}), do: [resource_id, nil]

  defp grant_group_resource_ids({:instance, _entity_type, resource_id}), do: [resource_id]

  defp grant_group_resource_ids({:type, _entity_type}), do: [nil]

  defp grant_group_resource_ids(:global), do: [nil]

  defp grant_group_rows({{user_id, nil}, _scopes}, session_user_id) do
    RoleGrant
    |> Query.filter(user_id: user_id, resource_type: nil, resource_id: nil)
    |> run_carried_grants_query(session_user_id)
  end

  defp grant_group_rows({{user_id, entity_type}, scopes}, session_user_id) do
    resource_ids =
      scopes
      |> Enum.flat_map(&grant_group_resource_ids/1)
      |> Enum.uniq()

    RoleGrant
    |> Query.filter(
      user_id: user_id,
      resource_type: RoleGrant.resource_type(entity_type),
      resource_id: resource_ids
    )
    |> run_carried_grants_query(session_user_id)
  end

  defp grant_scope_groups(scopes) do
    scopes
    |> Enum.group_by(&grant_group_key/1, fn {_user_id, scope} -> scope end)
    |> Enum.sort_by(fn {{user_id, entity_type}, _scopes} -> {user_id, inspect(entity_type)} end)
  end

  defp grant_exists?(_actor_user_id, _scope, [], _source), do: false

  # No stored grant can name an id the framework never generated, so an id in any other
  # spelling holds nothing - checking access with one is a denial, not an error.
  defp grant_exists?(actor_user_id, scope, role_names, source) do
    if Validator.attribute_value_valid?(actor_user_id, :uuid) do
      grant_held?(actor_user_id, scope, role_names, source)
    else
      false
    end
  end

  # Every rule kind funnels through here, so this is the one place a render's questions can be
  # caught - and questions are all there is to catch: what runs below is an EXISTS, which answers
  # with a boolean and materializes no row.
  defp grant_held?(actor_user_id, scope, role_names, :stored) do
    Carry.record_grant_scope(actor_user_id, scope)

    query_grant_exists?(actor_user_id, scope, role_names)
  end

  # A check against a list the caller supplied is nobody's question: the rows are already in
  # hand, so there is nothing for a render to gather and nothing to record.
  defp grant_held?(actor_user_id, scope, role_names, grants) do
    Enum.any?(grants, &grant_matches?(&1, actor_user_id, scope, role_names))
  end

  # What the store's own statement asks, asked of a row already read: the same comparison per
  # column, nil included, which is what keeps the two ways of answering one rule in step.
  defp grant_matches?(grant, actor_user_id, scope, role_names) do
    grant.user_id == actor_user_id and grant.role in role_names and scope_matches?(grant, scope)
  end

  defp run_carried_grants_query(query, session_user_id) do
    query
    |> Query.normalize()
    |> QueryRunner.run_policied(DB.mapping(), session_user_id)
  end

  defp grantee_fk_constraint do
    %{columns: columns} = Map.fetch!(DB.mapping(), RoleGrant)

    columns
    |> Enum.find(&(&1.name == "user_id"))
    |> Map.fetch!(:fk_constraint)
  end

  defp guard_last_managing_role!(entity_type, resource_id, role, role_names) do
    if role in role_names and count_managing_grants(entity_type, resource_id, role_names) <= 1 do
      raise Hologram.AccessDeniedError,
            "cannot revoke the last role managing #{inspect(entity_type)} #{inspect(resource_id)} - transfer ownership first"
    end

    :ok
  end

  # Enum params are cast to their column's type in SQL rather than the columns to text, so
  # grant lookups keep using the store's unique index.
  defp qualified_enum_type(column_name) do
    %{columns: columns} = Map.fetch!(DB.mapping(), RoleGrant)

    enum_type =
      columns
      |> Enum.find(&(&1.name == column_name))
      |> Map.fetch!(:sql_type)

    ~s("hologram_data".#{Mapper.quote_identifier(enum_type)})
  end

  # sobelow_skip ["SQL.Query"]
  defp query_grant_exists?(actor_user_id, scope, role_names) do
    {scope_condition, scope_params} = scope_condition(scope)
    role_placeholder = "$#{length(scope_params) + 2}"

    statement = """
    SELECT EXISTS (
      SELECT 1 FROM "hologram_data"."hologram_role_grant"
      WHERE "user_id" = $1
        AND #{scope_condition}
        AND "role" = ANY(#{role_placeholder}::#{qualified_enum_type("role")}[])
    )
    """

    role_values = Enum.map(role_names, &Codec.encode(&1, :enum))
    params = Enum.concat([[Codec.encode(actor_user_id, :uuid)], scope_params, [role_values]])

    {:ok, %{rows: [[grant_exists?]]}} = Connection.query(statement, params)

    grant_exists?
  end

  defp related_id(entity, relationship_name) do
    Map.fetch!(entity, String.to_existing_atom("#{relationship_name}_id"))
  end

  defp relationship_target(entity_type, relationship_name) do
    {_name, target_type, _opts} =
      Enum.find(entity_type.__relationships__(), fn {name, _type, _opts} ->
        name == relationship_name
      end)

    target_type
  end

  defp resource_reference(resource) when is_struct(resource) do
    {resource.__struct__, validate_id!(resource.id, "resource")}
  end

  defp resource_reference(resource), do: {resource, nil}

  defp resource_type_value(entity_type) do
    entity_type
    |> RoleGrant.resource_type()
    |> Atom.to_string()
  end

  defp scope_matches?(grant, :global) do
    grant.resource_type == nil and grant.resource_id == nil
  end

  defp scope_matches?(grant, {:instance, entity_type, resource_id}) do
    grant.resource_type == RoleGrant.resource_type(entity_type) and
      grant.resource_id == resource_id
  end

  # An own-scope check matches the row naming the resource AND the type-wide row, which is the
  # nil the store's condition admits beside the id.
  defp scope_matches?(grant, {:own, entity_type, resource_id}) do
    grant.resource_type == RoleGrant.resource_type(entity_type) and
      grant.resource_id in [resource_id, nil]
  end

  defp scope_matches?(grant, {:type, entity_type}) do
    grant.resource_type == RoleGrant.resource_type(entity_type) and grant.resource_id == nil
  end

  defp scope_condition({:own, entity_type, resource_id}) do
    condition =
      ~s|"resource_type" = $2::#{qualified_enum_type("resource_type")} | <>
        ~s|AND ("resource_id" = $3 OR "resource_id" IS NULL)|

    {condition, [resource_type_value(entity_type), Codec.encode(resource_id, :uuid)]}
  end

  defp scope_condition({:instance, entity_type, resource_id}) do
    condition =
      ~s|"resource_type" = $2::#{qualified_enum_type("resource_type")} AND "resource_id" = $3|

    {condition, [resource_type_value(entity_type), Codec.encode(resource_id, :uuid)]}
  end

  defp scope_condition({:type, entity_type}) do
    condition =
      ~s|"resource_type" = $2::#{qualified_enum_type("resource_type")} AND "resource_id" IS NULL|

    {condition, [resource_type_value(entity_type)]}
  end

  defp scope_condition(:global) do
    {~s|"resource_type" IS NULL AND "resource_id" IS NULL|, []}
  end

  defp undo_grant_effect(%{op: :put_entity, entity_id: id}, grants) do
    Enum.reject(grants, &(&1.id == id))
  end

  defp undo_grant_effect(%{op: :del_entity, data: data}, grants) do
    [Outbox.entity_from_data(RoleGrant, data) | grants]
  end

  defp unknown_global_role_message(role) do
    case Reflection.list_roles() do
      [] ->
        "unknown global role #{inspect(role)} - no module is defined with use Hologram.Role"

      role_modules ->
        declared_roles =
          role_modules
          |> Enum.sort_by(&inspect/1)
          |> Enum.map_join(", ", &inspect/1)

        "unknown global role #{inspect(role)} - defined global roles are: #{declared_roles}"
    end
  end

  # The refusal teaches: which roles the acting user holds that reach the resource, what those
  # may grant (or revoke) there, whether the role asked for extends one of them, and the line
  # that would cover it if the omission was not intended.
  defp unqualified_role_message(entity_type, resource_id, actor_user_id, role, operation) do
    verb = operation_verb(operation)
    resource = "#{inspect(entity_type)} #{inspect(resource_id)}"

    case held_role_names(actor_user_id, entity_type, resource_id) do
      [] ->
        "the acting user holds no role on #{resource} that may #{verb} #{inspect(role)}"

      held_names ->
        covered = covered_role_names(entity_type, resource_id, actor_user_id, operation)

        "the acting user holds #{join_role_names(held_names)} on #{resource}, which may #{verb} #{covered_description(covered, role)}. " <>
          extends_sentence(entity_type, held_names, role) <>
          "Declare `allow {#{inspect(operation)}, #{inspect(role)}}, to: #{inspect(single_or_list(held_names))}` on #{inspect(entity_type)} if that is intended."
    end
  end

  defp covered_description([], role), do: "no role there, #{inspect(role)} included"

  defp covered_description(covered, role),
    do: "#{join_role_names(covered)} but not #{inspect(role)}"

  # The declared roles the acting user may grant (or revoke) on the resource - the same question
  # the gate asked, once per role.
  defp covered_role_names(entity_type, resource_id, actor_user_id, operation) do
    resource = gate_resource(entity_type, resource_id)

    entity_type.__roles__()
    |> Enum.map(fn {name, _opts} -> name end)
    |> Enum.filter(&can?(actor_user_id, {operation, &1}, resource))
  end

  # Named when the role asked for extends a held own role - the case the derived default exists
  # for. A held global role module sits in no own chain.
  defp extends_sentence(entity_type, held_names, role) do
    declared_names = Enum.map(entity_type.__roles__(), fn {name, _opts} -> name end)

    extended =
      Enum.filter(held_names, fn held ->
        held != role and held in declared_names and role in Entity.expand_role(entity_type, held)
      end)

    case extended do
      [] -> ""
      _extended -> "#{inspect(role)} extends #{join_role_names(extended)}, so it holds more. "
    end
  end

  # A gate line reads nothing of the row but its id - the policy validator refuses predicates and
  # delegations on one - so the evaluator is asked about an id-only struct.
  defp gate_resource(entity_type, resource_id), do: struct(entity_type, id: resource_id)

  # The roles the acting user holds that reach the resource, as the gate reads them: on the row
  # itself or on its whole type, and the global roles held app-wide. Sorted, own names first.
  defp held_role_names(actor_user_id, entity_type, resource_id) do
    resource_type = RoleGrant.resource_type(entity_type)

    RoleGrant
    |> Query.filter(user_id: actor_user_id)
    |> Query.normalize()
    |> QueryRunner.run(DB.mapping())
    |> Enum.filter(fn grant ->
      (grant.resource_type == resource_type and grant.resource_id in [resource_id, nil]) or
        (grant.resource_type == nil and grant.resource_id == nil)
    end)
    |> Enum.map(& &1.role)
    |> Enum.sort_by(&{Reflection.alias?(&1), &1})
  end

  defp join_role_names(role_names), do: Enum.map_join(role_names, " and ", &inspect/1)

  defp operation_verb(:grant_role), do: "grant"

  defp operation_verb(:revoke_role), do: "revoke"

  defp signed_in_write_message(verb) do
    "a role is #{verb} only by a signed-in user - nobody is signed in"
  end

  defp single_or_list([role_name]), do: role_name

  defp single_or_list(role_names), do: role_names

  # A grant row carrying no resource id is one of the two trusted-only shapes, told apart by
  # whether it names a type at all.
  defp trusted_scope(%RoleGrant{resource_type: nil}), do: "global"

  defp trusted_scope(%RoleGrant{}), do: "type-wide"

  defp trusted_write_message(scope, verb) do
    "#{scope} roles are #{verb} only by trusted code running without an acting user"
  end

  defp validate_declared_role!(entity_type, role) do
    declared_names = Enum.map(entity_type.__roles__(), fn {name, _opts} -> name end)

    if role not in declared_names do
      declared_roles = Enum.map_join(declared_names, ", ", &inspect/1)

      raise ArgumentError,
            "unknown role #{inspect(role)} for #{inspect(entity_type)} - declared roles are: #{declared_roles}"
    end
  end

  defp validate_global_role!(role) do
    if not Reflection.role?(role) do
      raise ArgumentError, unknown_global_role_message(role)
    end

    :ok
  end

  defp validate_id!(id, subject) do
    if not Validator.attribute_value_valid?(id, :uuid) do
      raise ArgumentError,
            "invalid #{subject} id #{inspect(id)} - entity ids are canonical lowercase 8-4-4-4-12 UUID strings"
    end

    id
  end

  defp validate_user_id!(user_or_id) do
    user_or_id
    |> actor_user_id()
    |> validate_id!("user")
  end

  # The grant goes through the internal entity write path, so it is validated, stamped and
  # encoded like any row - the public write surface is closed to role grants on purpose.
  defp write_grant(user_id, resource_type, resource_id, role) do
    # One identity scheme for the store, whoever writes it: a grant made here and the same grant
    # made in a browser are one row, because both derive the id from the grant itself.
    grant = %RoleGrant{
      id: RoleGrant.derive_id(user_id, resource_type, resource_id, role),
      granted_by_id: Context.actor_user_id(),
      resource_id: resource_id,
      resource_type: resource_type,
      role: role,
      user_id: user_id
    }

    EntityOperations.create_if_absent(grant)

    # Both verbs are documented idempotent - granting a role the user already holds keeps the
    # original grant - so whether a row went in is nothing a caller of theirs asked about.
    :ok
  rescue
    error in Postgrex.Error ->
      # A grant row references the user table twice - the grantee and whoever granted it - so the
      # violated constraint is what says which id was unknown. Only the grantee's is the caller's
      # mistake: an acting user is authorized by a grant of their own, whose reference keeps their
      # row undeletable, so their id going missing mid-write is a database story, not a caller one.
      grantee_constraint = grantee_fk_constraint()

      case error.postgres do
        %{code: :foreign_key_violation, constraint: ^grantee_constraint} ->
          message =
            "unknown user id #{inspect(user_id)} - roles are granted only to existing users"

          reraise ArgumentError, [message: message], __STACKTRACE__

        _other_violation ->
          reraise error, __STACKTRACE__
      end
  end
end
