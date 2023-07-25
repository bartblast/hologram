defmodule Hologram.Commons.CryptographicUtils do
  @doc """
  Calculates the SHA-256 cryptographic digest of the input data.
  If the `encode_as_hex` param is `true` then hexadecimal string is returned, or binary otherwise.

  ## Examples

      iex> digest("Hologram", true)
      "ddff15a2da596882cfd545132004c8e7355e457517a3874f4853cc6ff1110c2e"

      iex> digest("Hologram", false)
      <<221, 255, 21, 162, 218, 89, 104, 130, 207, 213, 69, 19, 32, 4, 200, 231, 53,
        94, 69, 117, 23, 163, 135, 79, 72, 83, 204, 111, 241, 17, 12, 46>>
  """
  @spec digest(binary, boolean) :: String.t() | binary
  def digest(data, encode_as_hex \\ true)

  def digest(data, false) do
    :crypto.hash(:sha256, data)
  end

  def digest(data, true) do
    data
    |> digest(false)
    |> Base.encode16()
    |> String.downcase()
  end
end
