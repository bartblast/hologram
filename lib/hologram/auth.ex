defmodule Hologram.Auth do
  @moduledoc false

  alias Hologram.Auth.Context
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Entity.Validator
  alias Hologram.Policy
  alias Hologram.Policy.Evaluator
  alias Hologram.RoleGrant

  @doc """
  Returns true when the given user may perform the given action on the given entity, or false otherwise.

  Takes the user entity or a bare user id, and nil for an anonymous session - rules referencing
  the acting user never match then. An action the entity type declares no rule for is denied.
  """
  @spec can?(struct | String.t() | nil, atom, struct) :: boolean
  def can?(user_or_id, action, entity) do
    policy = Policy.build(entity.__struct__)

    Evaluator.grants?(policy, action, entity, actor_user_id(user_or_id), &check_requirement/3)
  end

  @doc """
  Grants the given global role to the given user and returns :ok.

  Takes the user entity or a bare user id. The role must be declared with scope :global on
  some entity type - a global role is held without a resource, so it applies everywhere.
  Granting a role the user already holds keeps the original grant, metadata included.
  """
  @spec grant_role(struct | String.t(), atom) :: :ok
  def grant_role(user_or_id, role) do
    user_id = validate_user_id!(user_or_id)
    global_role_names = Policy.global_role_names()

    if role not in global_role_names do
      raise ArgumentError, unknown_global_role_message(role, global_role_names)
    end

    authorize_trusted_write!("global", "granted")

    write_grant(user_id, nil, nil, role)
  end

  @doc """
  Grants the given role on the given resource to the given user and returns :ok.

  Takes the user entity or a bare user id. An entity struct grants the role on that row, an
  entity type module grants it on every row of the type. The role must be declared on the
  resource's entity type. Granting a role the user already holds on the same resource keeps
  the original grant, metadata included.
  """
  @spec grant_role(struct | String.t(), struct | module, atom) :: :ok
  def grant_role(user_or_id, resource, role) do
    user_id = validate_user_id!(user_or_id)
    {entity_type, resource_id} = resource_reference(resource)

    validate_declared_role!(entity_type, role)
    authorize_grant!(entity_type, resource_id)

    write_grant(user_id, RoleGrant.resource_type(entity_type), resource_id, role)
  end

  @doc """
  Revokes the given global role from the given user and returns :ok.

  Takes the user entity or a bare user id. Revoking a role the user does not hold is a no-op.
  """
  @spec revoke_role(struct | String.t(), atom) :: :ok
  def revoke_role(user_or_id, role) do
    user_id = validate_user_id!(user_or_id)
    global_role_names = Policy.global_role_names()

    if role not in global_role_names do
      raise ArgumentError, unknown_global_role_message(role, global_role_names)
    end

    authorize_trusted_write!("global", "revoked")

    delete_grant(user_id, nil, nil, role)
  end

  @doc """
  Revokes the given role on the given resource from the given user and returns :ok.

  Takes the user entity or a bare user id, and an entity struct or entity type module for
  the resource. Users may always revoke their own roles, which is how a member leaves a
  resource - revoking someone else's requires managing that resource's roles. The last role
  managing a resource can't be revoked, so a resource never loses its last manager.
  Revoking a role the user does not hold is a no-op.
  """
  @spec revoke_role(struct | String.t(), struct | module, atom) :: :ok
  def revoke_role(user_or_id, resource, role) do
    user_id = validate_user_id!(user_or_id)
    {entity_type, resource_id} = resource_reference(resource)

    validate_declared_role!(entity_type, role)
    authorize_revoke!(entity_type, resource_id, user_id, role)

    delete_grant(user_id, RoleGrant.resource_type(entity_type), resource_id, role)
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

  # Granting on a resource requires holding a role that manages its grants. Running with no
  # actor is the trusted tier - scripts, consoles and seeds grant whatever they need.
  defp authorize_grant!(_entity_type, nil), do: authorize_trusted_write!("type-wide", "granted")

  defp authorize_grant!(entity_type, resource_id) do
    case Context.actor_user_id() do
      nil ->
        :ok

      actor_user_id ->
        role_names = Policy.manage_roles_qualifying_roles(entity_type)

        if not holds_role?(actor_user_id, entity_type, resource_id, role_names) do
          raise Hologram.AccessDeniedError, unmanaged_resource_message(entity_type, resource_id)
        end

        :ok
    end
  end

  # Users may always revoke their own roles - leaving a resource needs no permission. Taking
  # a role from someone else does, and the last managing role never goes, so a resource can
  # never be left with nobody able to manage it.
  defp authorize_revoke!(_entity_type, nil, _user_id, _role) do
    authorize_trusted_write!("type-wide", "revoked")
  end

  defp authorize_revoke!(entity_type, resource_id, user_id, role) do
    case Context.actor_user_id() do
      nil ->
        :ok

      actor_user_id ->
        role_names = Policy.manage_roles_qualifying_roles(entity_type)

        if actor_user_id != user_id and
             not holds_role?(actor_user_id, entity_type, resource_id, role_names) do
          raise Hologram.AccessDeniedError, unmanaged_resource_message(entity_type, resource_id)
        end

        guard_last_managing_role!(entity_type, resource_id, role, role_names)
    end
  end

  defp authorize_trusted_write!(scope, verb) do
    if Context.actor_user_id() do
      raise Hologram.AccessDeniedError,
            "#{scope} roles are #{verb} only by trusted code running without an acting user"
    end

    :ok
  end

  # TODO: grant references and delegations deny until the role grant store can answer them.
  defp check_requirement(_requirement, _entity, _actor_user_id), do: false

  # sobelow_skip ["SQL.Query"]
  defp count_managing_grants(entity_type, resource_id, role_names) do
    statement = """
    SELECT count(*) FROM "hologram_data"."hologram_role_grant"
    WHERE "resource_type" = $1::#{qualified_enum_type("resource_type")}
      AND "resource_id" = $2
      AND "role" = ANY($3::#{qualified_enum_type("role")}[])
    """

    params = [
      resource_type_value(entity_type),
      Codec.encode(resource_id, :uuid),
      Enum.map(role_names, &Atom.to_string/1)
    ]

    {:ok, %{rows: [[count]]}} = Connection.query(statement, params)

    count
  end

  # Nils encode the type-wide and global grant shapes, so the delete matches them as values -
  # the same comparison the store's unique index makes.
  # sobelow_skip ["SQL.Query"]
  defp delete_grant(user_id, resource_type, resource_id, role) do
    statement = """
    DELETE FROM "hologram_data"."hologram_role_grant"
    WHERE "user_id" = $1
      AND "resource_type" IS NOT DISTINCT FROM $2::#{qualified_enum_type("resource_type")}
      AND "resource_id" IS NOT DISTINCT FROM $3
      AND "role" = $4::#{qualified_enum_type("role")}
    """

    params = [
      Codec.encode(user_id, :uuid),
      resource_type && Atom.to_string(resource_type),
      Codec.encode(resource_id, :uuid),
      Atom.to_string(role)
    ]

    {:ok, _result} = Connection.query(statement, params)

    :ok
  end

  defp guard_last_managing_role!(entity_type, resource_id, role, role_names) do
    if role in role_names and count_managing_grants(entity_type, resource_id, role_names) <= 1 do
      raise Hologram.AccessDeniedError,
            "cannot revoke the last role managing #{inspect(entity_type)} #{inspect(resource_id)} - transfer ownership first"
    end

    :ok
  end

  defp holds_role?(_actor_user_id, _entity_type, _resource_id, []), do: false

  # sobelow_skip ["SQL.Query"]
  defp holds_role?(actor_user_id, entity_type, resource_id, role_names) do
    statement = """
    SELECT EXISTS (
      SELECT 1 FROM "hologram_data"."hologram_role_grant"
      WHERE "user_id" = $1
        AND "resource_type" = $2::#{qualified_enum_type("resource_type")}
        AND "resource_id" = $3
        AND "role" = ANY($4::#{qualified_enum_type("role")}[])
    )
    """

    params = [
      Codec.encode(actor_user_id, :uuid),
      resource_type_value(entity_type),
      Codec.encode(resource_id, :uuid),
      Enum.map(role_names, &Atom.to_string/1)
    ]

    {:ok, %{rows: [[holds_role?]]}} = Connection.query(statement, params)

    holds_role?
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

  defp resource_reference(resource) when is_struct(resource) do
    {resource.__struct__, validate_id!(resource.id, "resource")}
  end

  defp resource_reference(resource), do: {resource, nil}

  defp resource_type_value(entity_type) do
    entity_type
    |> RoleGrant.resource_type()
    |> Atom.to_string()
  end

  defp unknown_global_role_message(role, []) do
    "unknown global role #{inspect(role)} - no role is declared with scope: :global"
  end

  defp unknown_global_role_message(role, global_role_names) do
    declared_roles = Enum.map_join(global_role_names, ", ", &inspect/1)

    "unknown global role #{inspect(role)} - declared global roles are: #{declared_roles}"
  end

  defp unmanaged_resource_message(entity_type, resource_id) do
    "not allowed to manage the roles of #{inspect(entity_type)} #{inspect(resource_id)}"
  end

  defp validate_declared_role!(entity_type, role) do
    declared_names = Enum.map(entity_type.__roles__(), fn {name, _opts} -> name end)

    if role not in declared_names do
      declared_roles = Enum.map_join(declared_names, ", ", &inspect/1)

      raise ArgumentError,
            "unknown role #{inspect(role)} for #{inspect(entity_type)} - declared roles are: #{declared_roles}"
    end
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
    grant = %RoleGrant{
      id: Entity.generate_id(),
      granted_by_id: Context.actor_user_id(),
      resource_id: resource_id,
      resource_type: resource_type,
      role: role,
      user_id: user_id
    }

    EntityOperations.create_if_absent(grant)
  rescue
    error in Postgrex.Error ->
      if error.postgres.code == :foreign_key_violation do
        message = "unknown user id #{inspect(user_id)} - roles are granted only to existing users"

        reraise ArgumentError, [message: message], __STACKTRACE__
      else
        reraise error, __STACKTRACE__
      end
  end
end
