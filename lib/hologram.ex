defmodule Hologram do
  @env Mix.env()

  @doc """
  Returns the current environment.
  """
  @spec env() :: atom
  def env, do: @env
end
