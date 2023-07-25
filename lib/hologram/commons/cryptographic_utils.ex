defmodule Hologram.Commons.CryptographicUtils do
  @doc """
  Calculates the SHA-256 cryptographic digest of the input data.
  If the `encode_as_hex` param is `true` then hexadecimal string is returned, or binary otherwise.
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
