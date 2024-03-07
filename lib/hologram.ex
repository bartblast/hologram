defmodule Hologram do
  @env Application.compile_env!(:hologram, :env)

  @doc """
  Get current environment name.
  """
  @spec env() :: atom
  def env, do: @env
end
