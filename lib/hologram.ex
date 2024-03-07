defmodule Hologram do
  @doc """
  Get current environment name.

  It is implemented in such a way as to avoid requiring to specify the environment in the project config.
  """
  @spec env() :: atom
  def env do
    regex = ~r"^.+/([^/]+)/lib/hologram$"
    lib_dir = to_string(:code.lib_dir(:hologram))
    [_lib_dir, env] = Regex.run(regex, lib_dir)

    String.to_existing_atom(env)
  end
end
