defmodule Hologram.Auth do
  @moduledoc false

  alias Hologram.Auth.Context
  alias Hologram.Policy
  alias Hologram.Policy.Evaluator

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
  Returns the entity id of the user the running work is authorized as, or nil when the
  session is anonymous. Framework wrappers set the actor around the work they run, so the
  value always comes from an authenticated session and never from anything a client sends.
  """
  @spec user_id() :: String.t() | nil
  defdelegate user_id, to: Context, as: :actor_user_id

  defp actor_user_id(%{id: id}), do: id

  defp actor_user_id(user_id), do: user_id

  # TODO: grant references and delegations deny until the role grant store can answer them.
  defp check_requirement(_requirement, _entity, _actor_user_id), do: false
end
