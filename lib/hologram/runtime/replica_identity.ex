defmodule Hologram.Runtime.ReplicaIdentity do
  @moduledoc false

  # A replica's identity as the server minted it: a replica id and a signed statement of whom it
  # belongs to - the signed-in user, or the session when nobody is. The statement is what a batch
  # presents beside its replica id, and it proves the presenting session is the one the id was
  # minted for without any registry, so the check holds offline and on any node. Signed, not
  # encrypted: it is a statement rather than a secret, and presenting it proves nothing without
  # the session it names.

  @salt "hologram replica identity"

  @type subject :: {:session, String.t()} | {:user, term}

  @doc """
  Returns a signed statement that the given replica id belongs to the given user - or, when there
  is no user, to the given session.
  """
  @spec issue(String.t(), String.t(), term | nil) :: String.t()
  def issue(replica_id, session_id, user_id) do
    Phoenix.Token.sign(
      Hologram.secret_key_base(),
      @salt,
      {replica_id, subject(session_id, user_id)}
    )
  end

  @doc """
  Returns `:ok` when the given statement is genuine and says the given replica id belongs to the
  given user, or to the given session - a session keeps an identity minted before somebody signed
  in on it. Returns `{:error, :mismatch}` for a genuine statement about another replica or another
  owner, and `{:error, :invalid}` for one that is not genuine.
  """
  @spec verify(String.t(), String.t(), String.t(), term | nil) ::
          :ok | {:error, :invalid | :mismatch}
  def verify(token, replica_id, session_id, user_id) do
    # No expiry: the binding is the security, and a batch queued offline for days must still be
    # presentable.
    case Phoenix.Token.verify(Hologram.secret_key_base(), @salt, token, max_age: :infinity) do
      {:ok, {^replica_id, {:user, ^user_id}}} when user_id != nil ->
        :ok

      # A session's id does not change at login, so a statement minted for an anonymous visitor
      # keeps working after they sign in - what changes is only what the NEXT page load mints.
      {:ok, {^replica_id, {:session, ^session_id}}} ->
        :ok

      {:ok, _statement} ->
        {:error, :mismatch}

      {:error, _reason} ->
        {:error, :invalid}
    end
  end

  defp subject(session_id, nil), do: {:session, session_id}
  defp subject(_session_id, user_id), do: {:user, user_id}
end
