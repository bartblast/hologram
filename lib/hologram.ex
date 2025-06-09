defmodule Hologram do
  @mix_env Mix.env()

  @doc """
  Returns the current environment.
  """
  @spec env() :: atom
  def env, do: @mix_env
end
