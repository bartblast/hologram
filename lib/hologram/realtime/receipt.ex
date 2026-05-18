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

  @salt "hologram subscription receipt"

  @doc """
  Signs the given receipt via `Phoenix.Token` using the host app's
  `SECRET_KEY_BASE` env variable. Returns the signed token as a string.
  """
  @spec sign(t) :: String.t()
  def sign(%__MODULE__{} = receipt) do
    payload =
      {receipt.instance_id, receipt.user_id, receipt.channel, receipt.cid, receipt.created_at}

    Phoenix.Token.sign(secret_key_base(), @salt, payload)
  end

  defp secret_key_base do
    System.fetch_env!("SECRET_KEY_BASE")
  end
end
