defmodule Hologram do
  @mix_env Mix.env()

  @doc """
  Returns the current environment.
  """
  @spec env() :: atom
  def env do
    System.get_env("MIX_ENV") || @mix_env
  end
end
