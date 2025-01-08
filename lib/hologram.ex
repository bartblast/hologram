defmodule Hologram do
  @mix_env Mix.env()

  @doc """
  Returns the current environment.
  """
  @spec env() :: atom
  def env do
    regex = ~r"^.+/_build/([^/]+)/.+$"
    lib_dir = to_string(:code.lib_dir(:hologram))

    case Regex.run(regex, lib_dir) do
      [_lib_dir, env] -> String.to_existing_atom(env)
      _fallback -> @mix_env
    end
  end
end
