defmodule Hologram.Realtime.Receipt do
  @moduledoc false

  defstruct [:channel, :cid, :created_at, :instance_id, :user_id]

  @type t :: %__MODULE__{
          channel: atom | tuple,
          cid: String.t(),
          created_at: integer,
          instance_id: String.t(),
          user_id: term | nil
        }

  @max_age_seconds 72 * 60 * 60
  @salt "hologram subscription receipt"

  @doc """
  Mints a fresh receipt for the given binding (`channel` + `cid`) under the
  given instance and user identity, stamps `created_at` to the current system
  time in milliseconds, and returns the signed token.
  """
  @spec issue(atom | tuple, String.t(), String.t(), term | nil) :: String.t()
  def issue(channel, cid, instance_id, user_id) do
    sign(%__MODULE__{
      channel: channel,
      cid: cid,
      created_at: System.system_time(:millisecond),
      instance_id: instance_id,
      user_id: user_id
    })
  end

  @doc """
  Verifies and decodes a token previously produced by `issue/4`. Returns
  `{:ok, receipt}` on success, or `{:error, reason}` from `Phoenix.Token.verify/4`
  on tampering or expiry.

  Default `max_age` is 72 hours; callers can override via the `:max_age` option
  (in seconds), mainly to exercise expiry deterministically in tests.
  """
  @spec verify(String.t(), keyword) :: {:ok, t} | {:error, atom}
  def verify(token, opts \\ []) do
    max_age = Keyword.get(opts, :max_age, @max_age_seconds)

    case Phoenix.Token.verify(Hologram.secret_key_base(), @salt, token, max_age: max_age) do
      {:ok, {instance_id, user_id, channel, cid, created_at}} ->
        {:ok,
         %__MODULE__{
           channel: channel,
           cid: cid,
           created_at: created_at,
           instance_id: instance_id,
           user_id: user_id
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sign(%__MODULE__{} = receipt) do
    payload =
      {receipt.instance_id, receipt.user_id, receipt.channel, receipt.cid, receipt.created_at}

    Phoenix.Token.sign(Hologram.secret_key_base(), @salt, payload)
  end
end
