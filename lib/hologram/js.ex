defmodule Hologram.JS do
  @moduledoc """
  JavaScript interop.
  """

  @doc """
  Executes JavaScript code.
  Server-side implementation is just a dummy. The actual implementation is on the client-side.
  """
  @spec exec(String.t()) :: String.t()
  def exec(code), do: code

  @doc """
  Provides a convenient syntax for executing JavaScript code using the ~JS sigil.
  """
  @doc since: "1.15.0"
  def sigil_JS(code, []), do: exec(code)
end
