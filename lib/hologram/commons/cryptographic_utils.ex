defmodule Hologram.Commons.CryptographicUtils do
  @moduledoc false

  @doc """
  Calculates the cryptographic digest of the input data using the given algorithm (such as :md5, :sha256, etc.).
  Output format can be either `:hex` (hexadecimal string) or `:binary` (binary data).

  ## Examples

      iex> digest("Hologram", :sha256, :hex)
      "ddff15a2da596882cfd545132004c8e7355e457517a3874f4853cc6ff1110c2e"

      iex> digest("Hologram", false)
      <<221, 255, 21, 162, 218, 89, 104, 130, 207, 213, 69, 19, 32, 4, 200, 231, 53,
        94, 69, 117, 23, 163, 135, 79, 72, 83, 204, 111, 241, 17, 12, 46>>
  """
  @spec digest(binary, atom, :binary | :hex) :: String.t() | binary
  def digest(data, algo, format)

  def digest(data, algo, :binary) do
    :crypto.hash(algo, data)
  end

  def digest(data, algo, :hex) do
    data
    |> digest(algo, :binary)
    |> Base.encode16()
    |> String.downcase()
  end
end
