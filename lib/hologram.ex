defmodule Hologram do
  @doc """
  Returns the current environment.
  """
  @spec env() :: atom
  def env do
    env_str = System.get_env("HOLOGRAM_ENV") || System.get_env("MIX_ENV")

    if env_str do
      String.to_existing_atom(env_str)
    else
      detect_env()
    end
  end

  defp detect_env do
    if Process.whereis(ExUnit.Server) do
      :test
    else
      :dev
    end
  end
end
