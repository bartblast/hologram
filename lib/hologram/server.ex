defmodule Hologram.Server do
  alias Hologram.Component.Action
  alias Hologram.Server.Cookie
  alias Hologram.Server.Metadata

  defstruct cookies: %{}, next_action: nil, session: %{}, __meta__: %Metadata{}

  @type t :: %__MODULE__{
          cookies: %{String.t() => any()},
          next_action: Action.t() | nil,
          session: %{atom => any},
          __meta__: Metadata.t()
        }

  @doc """
  Returns the current system time in microseconds since the Unix epoch.
  """
  @callback timestamp() :: non_neg_integer

  @doc """
  Creates a new Hologram.Server struct from a Plug connection.

  Extracts cookies from the connection and initializes a server struct
  with those cookies. Other fields are set to their default values.

  ## Parameters

    * `conn` - A Plug connection struct

  ## Examples

      iex> conn = %Plug.Conn{cookies: %{"use_id" => "abc123"}}
      iex> server = Hologram.Server.from(conn)
      iex> server.cookies
      %{"user_id" => "abc123"}
  """
  @spec from(Plug.Conn.t()) :: t()
  def from(conn) do
    conn_with_cookies = Plug.Conn.fetch_cookies(conn)

    %__MODULE__{
      cookies: conn_with_cookies.cookies
    }
  end

  @doc """
  Adds a cookie to be set in the client's browser.

  ## Parameters

    * `server` - The server struct
    * `key` - The cookie name (must be a string)
    * `value` - The cookie value
    * `opts` - Optional cookie attributes (keyword list)

  ## Options

    * `:domain` - The domain for the cookie (default: `nil`)
    * `:http_only` - Whether the cookie should be accessible only through HTTP(S) requests (default: `true`)
    * `:max_age` - Maximum age in seconds (default: `nil`)
    * `:path` - The path for the cookie (default: `nil`)
    * `:same_site` - SameSite attribute (default: `:lax`)
    * `:secure` - Whether the cookie should only be sent over HTTPS (default: `true`)

  ## Examples

      iex> server = %Hologram.Server{}
      iex> put_cookie(server, "user_id", 123)
      %Hologram.Server{cookies: %{"user_id" => 123}}

      iex> server = %Hologram.Server{}
      iex> put_cookie(server, "theme", "dark", secure: false, path: "/admin")
      %Hologram.Server{cookies: %{"theme" => "dark"}}
  """
  @spec put_cookie(t(), String.t(), any(), keyword()) :: t()
  def put_cookie(server, key, value, opts \\ [])

  def put_cookie(server, key, value, opts) when is_binary(key) do
    new_cookies = Map.put(server.cookies, key, value)

    cookie_struct = struct!(Cookie, Keyword.put(opts, :value, value))

    new_cookie_ops =
      Map.put(server.__meta__.cookie_ops, key, {:put, impl().timestamp(), cookie_struct})

    new_meta = %{server.__meta__ | cookie_ops: new_cookie_ops}

    %{server | cookies: new_cookies, __meta__: new_meta}
  end

  # TODO: reconsider if this argument validation is needed once Elixir has static typing
  def put_cookie(_server, key, _value, _opts) do
    raise ArgumentError, """
    Cookie key must be a string, but received #{inspect(key)}.

    Cookie keys must be strings according to web standards.
    Try converting your key to a string: "#{key}".\
    """
  end

  @doc """
  Returns the current system time in microseconds since the Unix epoch.
  """
  @spec timestamp :: non_neg_integer
  def timestamp do
    :os.system_time(:microsecond)
  end

  defp impl do
    Application.get_env(:hologram, :server_impl, __MODULE__)
  end
end
