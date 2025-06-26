defmodule Hologram.Server.Cookie do
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
