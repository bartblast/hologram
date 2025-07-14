defmodule Hologram.Runtime.Cookie do
  @moduledoc false

  alias Hologram.Commons.StringUtils

  defstruct value: nil,
            domain: nil,
            http_only: true,
            max_age: nil,
            path: nil,
            same_site: :lax,
            secure: true

  @type t :: %__MODULE__{
          value: any(),
          domain: String.t() | nil,
          http_only: boolean(),
          max_age: integer() | nil,
          path: String.t() | nil,
          same_site: :lax | :none | :strict,
          secure: boolean()
        }

  @doc """
  Decodes a potentially encoded cookie value.

  If the input string starts with the Hologram-specific "%H" prefix, it removes
  the prefix, Base64-decodes the remaining string, and safely converts it back to the
  original Elixir term using binary_to_term/2 with the :safe option.

  If the input string does not have the "%H" prefix, it returns the string unchanged,
  treating it as a plain cookie value.

  ## Examples

      iex> Cookie.decode("%Hg3cFaGVsbG8")
      :hello

      iex> Cookie.decode("%Hg3QAAAABdwNrZXltAAAABXZhbHVl")
      %{key: "value"}

      iex> Cookie.decode("plain_cookie_value")
      "plain_cookie_value"
  """
  @spec decode(String.t()) :: any()
  def decode(encoded)

  # sobelow_skip ["Misc.BinToTerm"]
  def decode("%H" <> encoded) do
    encoded
    |> Base.decode64!(padding: false)
    |> :erlang.binary_to_term([:safe])
  end

  def decode(plain_string), do: plain_string

  @doc """
  Encodes a term into a Base64-encoded string with a Hologram-specific prefix.

  The term is first converted to binary using Erlang's term_to_binary/1, then
  Base64-encoded without padding, and finally prefixed with "%H" to identify
  it as a Hologram-encoded cookie value. The "%H" prefix is invalid in URL
  encoding, ensuring clear distinction from other cookie formats.

  ## Examples

      iex> Cookie.encode(:hello)
      "%Hg3cFaGVsbG8"

      iex> Cookie.encode(%{key: "value"})
      "%Hg3QAAAABdwNrZXltAAAABXZhbHVl"
  """
  @spec encode(term()) :: String.t()
  def encode(value) do
    value
    |> :erlang.term_to_binary()
    |> Base.encode64(padding: false)
    |> StringUtils.prepend("%H")
  end
end
