defmodule Hologram.Commons.PathUtils do
  @moduledoc false

  @doc """
  Returns the separator used in environment variables like PATH and NODE_PATH.

  ## Examples

      iex> env_path_separator()
      ":" # On Unix/Linux/macOS/BSD
      iex> env_path_separator()
      ";" # On Windows
  """
  @spec env_path_separator() :: String.t()
  def env_path_separator do
    case :os.type() do
      # Unix-like (Linux, macOS, BSD, Solaris, etc.)
      {:unix, _name} -> ":"
      # Windows (NT, CE, etc.)
      {:win32, _name} -> ";"
    end
  end

  @doc """
  Returns the appropriate path separator for the current operating system.

  ## Examples

      iex> path_separator()
      "/" # On Unix/Linux/macOS/BSD
      iex> path_separator()
      "\\" # On Windows
  """
  @spec path_separator() :: String.t()
  def path_separator do
    case :os.type() do
      # Unix-like (Linux, macOS, BSD, Solaris, etc.)
      {:unix, _name} -> "/"
      # Windows (NT, CE, etc.)
      {:win32, _name} -> "\\"
    end
  end
end
