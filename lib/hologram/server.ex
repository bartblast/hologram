defmodule Hologram.Server do
  alias Hologram.Commons.MapUtils
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
  with those cookies. Each cookie value is decoded using Cookie.decode/1,
  which handles both Hologram-encoded cookies (with "%H" prefix) and plain
  string cookies. The "hologram_session" cookie is automatically excluded
  from the server's cookies map. Other fields are set to their default values.

  ## Parameters

    * `conn` - A Plug connection struct

  ## Examples

      iex> conn = %Plug.Conn{cookies: %{"user_id" => "abc123"}}
      iex> server = Hologram.Server.from(conn)
      iex> server.cookies
      %{"user_id" => "abc123"}

      iex> conn = %Plug.Conn{cookies: %{"user_id" => "abc123", "hologram_session" => "xyz789"}}
      iex> server = Hologram.Server.from(conn)
      iex> server.cookies
      %{"user_id" => "abc123"}

      iex> # Hologram-encoded cookie is decoded to original term
      iex> conn = %Plug.Conn{cookies: %{"settings" => "%Hg3QAAAABdwNrZXltAAAABXZhbHVl"}}
      iex> server = Hologram.Server.from(conn)
      iex> server.cookies
      %{"settings" => %{key: "value"}}
  """
  @spec from(Plug.Conn.t()) :: t()
  def from(conn) do
    cookies =
      conn
      |> Plug.Conn.fetch_cookies()
      |> Map.fetch!(:cookies)
      |> Map.delete("hologram_session")
      |> Enum.map(fn {key, value} -> {key, Cookie.decode(value)} end)
      |> Enum.into(%{})

    %__MODULE__{
      cookies: cookies
    }
  end

  @doc """
  Computes the difference between cookies in two server structs.

  Returns a map with three keys describing the changes needed to transform 
  the cookies of `server_1` into the cookies of `server_2`:

  - `:added` - New cookies (exist in server_2 but not in server_1) as `{key, value}` tuples
  - `:edited` - Modified cookies (exist in both but with different values) as `{key, new_value}` tuples  
  - `:removed` - Deleted cookies (exist in server_1 but not in server_2) as a list of keys

  This function is useful for tracking cookie changes between different server states,
  such as before and after processing a request or command.

  ## Parameters

    * `server_1` - The previous server state
    * `server_2` - The new server state

  ## Examples

      iex> server_1 = %Hologram.Server{cookies: %{"user_id" => "123", "theme" => "light"}}
      iex> server_2 = %Hologram.Server{cookies: %{"user_id" => "456", "lang" => "en"}}
      iex> diff_cookies(server_1, server_2)
      %{
        added: [{"lang", "en"}],
        removed: ["theme"],
        edited: [{"user_id", "456"}]
      }

      iex> server_1 = %Hologram.Server{cookies: %{"user_id" => "123"}}
      iex> server_2 = %Hologram.Server{cookies: %{"user_id" => "123"}}
      iex> diff_cookies(server_1, server_2)
      %{added: [], removed: [], edited: []}
  """
  @spec diff_cookies(t(), t()) :: %{
          added: [{String.t(), any()}],
          removed: [String.t()],
          edited: [{String.t(), any()}]
        }
  def diff_cookies(server_1, server_2) do
    MapUtils.diff(server_1.cookies, server_2.cookies)
  end

  @doc """
  Retrieves a cookie value by key from the server struct.

  Returns the value associated with the given key, or the default value if the key
  does not exist in the cookies.

  ## Parameters

    * `server` - The server struct
    * `key` - The cookie name (string)
    * `default` - The value to return if the key is not found (default: `nil`)

  ## Examples

      iex> server = %Hologram.Server{cookies: %{"user_id" => "abc123"}}
      iex> get_cookie(server, "user_id")
      "abc123"

      iex> server = %Hologram.Server{cookies: %{"user_id" => "abc123"}}
      iex> get_cookie(server, "nonexistent")
      nil

      iex> server = %Hologram.Server{cookies: %{"user_id" => "abc123"}}
      iex> get_cookie(server, "nonexistent", "default_value")
      "default_value"
  """
  @spec get_cookie(t(), String.t(), any()) :: any()
  def get_cookie(server, key, default \\ nil) do
    Map.get(server.cookies, key, default)
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
