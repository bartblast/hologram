defmodule Hologram.Runtime.ContentSecurityPolicy do
  @moduledoc false

  @doc """
  Generates a nonce for one rendered page: 128 bits of randomness in the base64 alphabet a
  Content Security Policy nonce source is written in.

  ## Examples

      iex> generate_nonce()
      "f2KQWpHYuoeTQ1ZlbtX4pA=="
  """
  @spec generate_nonce() :: String.t()
  def generate_nonce do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode64()
  end
end
