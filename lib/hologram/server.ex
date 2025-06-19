defmodule Hologram.Server do
  alias Hologram.Component.Action

  defstruct cookies: %{}, next_action: nil, session: %{}

  @type t :: %__MODULE__{
          cookies: %{
            String.t() => %{
              value: any,
              domain: String.t() | nil,
              max_age: integer | nil,
              path: String.t() | nil,
              same_site: :lax | :none | :strict,
              secure: boolean
            }
          },
          next_action: Action.t() | nil,
          session: %{atom => any}
        }

  @doc """
  Adds a cookie to be set in the client's browser.

  ## Parameters

    * `server` - The server struct
    * `key` - The cookie name (must be a string)
    * `value` - The cookie value
    * `opts` - Optional cookie attributes (keyword list)

  ## Options

    * `:domain` - The domain for the cookie (default: `nil`)
    * `:max_age` - Maximum age in seconds (default: `nil`)
    * `:path` - The path for the cookie (default: `nil`)
    * `:same_site` - SameSite attribute (default: `:lax`)
    * `:secure` - Whether the cookie should only be sent over HTTPS (default: `true`)

  ## Examples

      iex> server = %Hologram.Server{}
      iex> put_cookie(server, "user_id", 123)
      %Hologram.Server{cookies: %{"session_id" => %{value: "abc123", domain: nil, max_age: nil, path: nil, same_site: :lax, secure: true}}}

      iex> server = %Hologram.Server{}
      iex> put_cookie(server, "theme", "dark", secure: false, path: "/")
      %Hologram.Server{cookies: %{"theme" => %{value: "dark", domain: nil, max_age: nil, path: "/", same_site: :lax, secure: false}}}
  """
  @spec put_cookie(t(), String.t(), any(), keyword()) :: t()
  def put_cookie(server, key, value, opts \\ [])

  def put_cookie(server, key, value, opts) when is_binary(key) do
    cookie = %{
      domain: Keyword.get(opts, :domain, nil),
      max_age: Keyword.get(opts, :max_age, nil),
      path: Keyword.get(opts, :path, nil),
      same_site: Keyword.get(opts, :same_site, :lax),
      secure: Keyword.get(opts, :secure, true),
      value: value
    }

    %{server | cookies: Map.put(server.cookies, key, cookie)}
  end

  # TODO: reconsider if this argument validation is needed once Elixir has static typing
  def put_cookie(_server, key, _value, _opts) do
    raise ArgumentError, """
    Cookie key must be a string, but received #{inspect(key)}.

    Cookie keys must be strings according to web standards.
    Try converting your key to a string: "#{key}".\
    """
  end
end
