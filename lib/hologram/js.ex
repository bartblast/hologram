defmodule Hologram.JS do
  @moduledoc """
  JavaScript interop.
  """

  @doc """
  Executes JavaScript code.
  Server-side implementation is just a dummy. The actual implementation is on the client-side.
  """
  @spec exec(String.t()) :: nil
  def exec(_code), do: nil
end
