defmodule Hologram do
  @mix_env Mix.env()

  @doc """
  Returns the current environment.
  """
  @spec env() :: atom
  def env do
    if env_string = System.get_env("MIX_ENV") do
      String.to_existing_atom(env_string)
    else
      @mix_env
    end
  end
end
