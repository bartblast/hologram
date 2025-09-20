defmodule Hologram.Config do
  @moduledoc false

  @doc """
  Adds internal Hologram configuration and merges in fallback configuration if not set.
  """
  @spec init(:atom, :atom) :: :ok
  def init(_otp_app, _env) do
    Application.put_env(:hologram, :mode, :standalone)

    :ok
  end
end
