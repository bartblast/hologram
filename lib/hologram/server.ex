defmodule Hologram.Server do
  alias Hologram.Component.Action
  alias Hologram.Runtime.Cookie
  alias Hologram.Runtime.PlugConnUtils
  alias Hologram.Runtime.Session
  alias Hologram.Server.Metadata

  defstruct cookies: %{}, next_action: nil, session: %{}, __meta__: %Metadata{}

  @type t :: %__MODULE__{
          cookies: %{String.t() => any()},
          next_action: Action.t() | nil,
          session: %{atom => any},
          __meta__: Metadata.t()
        }

  @doc """
  Removes a cookie from the server struct and marks it for deletion in the client's browser.

  If the cookie exists, it is removed from the server struct's cookies data and a delete 
  operation is recorded in the metadata. If the cookie does not exist, this function 
  is a no-op and returns the server struct unchanged.

  ## Parameters

    * `server` - The server struct
    * `key` - The cookie name to delete (must be a string)

  ## Examples

      iex> server = %Hologram.Server{cookies: %{"user_id" => "123", "theme" => "dark"}}
      iex> delete_cookie(server, "user_id")
      %Hologram.Server{cookies: %{"theme" => "dark"}}

      iex> # Deleting a nonexistent cookie is a no-op
      iex> server = %Hologram.Server{cookies: %{"theme" => "dark"}}
      iex> delete_cookie(server, "nonexistent")
      %Hologram.Server{cookies: %{"theme" => "dark"}}

      iex> server = %Hologram.Server{}
      iex> delete_cookie(server, "any_key")
      %Hologram.Server{cookies: %{}}
  """
  @spec delete_cookie(t, String.t()) :: t
  def delete_cookie(server, key)

  def delete_cookie(server, key) when is_map_key(server.cookies, key) do
    new_cookies = Map.delete(server.cookies, key)

    new_cookie_ops = Map.put(server.__meta__.cookie_ops, key, :delete)
    new_meta = %{server.__meta__ | cookie_ops: new_cookie_ops}

    %{server | cookies: new_cookies, __meta__: new_meta}
  end

  def delete_cookie(server, _key), do: server

  @doc """
  Removes a session entry from the server struct and marks it for deletion in the client's browser.

  If the session entry exists, it is removed from the server struct's session data and a delete 
  operation is recorded in the metadata. If the session entry does not exist, this function 
  is a no-op and returns the server struct unchanged.

  Atom keys are automatically converted to string.

  ## Parameters

    * `server` - The server struct
    * `key` - The session entry name to delete (atom or string)
  """
  @spec delete_session(t, atom | String.t()) :: t
  def delete_session(server, key)

  def delete_session(server, key) when is_atom(key) do
    delete_session(server, Atom.to_string(key))
  end

  def delete_session(server, key) when is_map_key(server.session, key) do
    new_session = Map.delete(server.session, key)

    new_session_ops = Map.put(server.__meta__.session_ops, key, :delete)
    new_meta = %{server.__meta__ | session_ops: new_session_ops}

    %{server | session: new_session, __meta__: new_meta}
  end

  def delete_session(server, _key), do: server

  @doc """
  Creates a new Hologram.Server struct from a Plug.Conn struct.

  Excludes "hologram_session" cookie.
  """
  @spec from(Plug.Conn.t()) :: t
  def from(%Plug.Conn{} = conn) do
    %__MODULE__{
      cookies: PlugConnUtils.extract_cookies(conn),
      session: Plug.Conn.get_session(conn)
    }
  end

  @doc """
  Retrieves a cookie value by key from the server struct.

  Returns the value associated with the given key or the default value if the key
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
  Retrieves the cookie operations recorded in the server struct's metadata.
  """
  @spec get_cookie_ops(t()) :: %{String.t() => Cookie.op()}
  def get_cookie_ops(server) do
    server.__meta__.cookie_ops
  end

  @doc """
  Retrieves the session operations recorded in the server struct's metadata.
  """
  @spec get_session_ops(t()) :: %{String.t() => Session.op()}
  def get_session_ops(server) do
    server.__meta__.session_ops
  end

  @doc """
  Retrieves a session value by key from the server struct.

  Returns the value associated with the given key or the default value if the key
  does not exist in the cookies.

  Atom keys are automatically converted to string.

  ## Parameters

    * `server` - The server struct
    * `key` - The session entry name (atom or string)
    * `default` - The value to return if the key is not found (default: `nil`)
  """
  @spec get_session(t(), atom | String.t(), any()) :: any()
  def get_session(server, key, default \\ nil)

  def get_session(server, key, default) when is_atom(key) do
    get_session(server, Atom.to_string(key), default)
  end

  def get_session(server, key, default) do
    Map.get(server.session, key, default)
  end

  @doc """
  Checks if the server struct has any recorded cookie operations.

  Returns `true` if there are any cookie operations (put or delete) in the
  server structs's metadata, `false` otherwise.

  ## Parameters

    * `server` - The server struct

  ## Examples

      iex> server = %Hologram.Server{}
      iex> has_cookie_ops?(server)
      false

      iex> server = %Hologram.Server{cookies: %{"user_id" => "123"}}
      iex> server = put_cookie(server, "theme", "dark")
      iex> has_cookie_ops?(server)
      true
  """
  @spec has_cookie_ops?(t) :: boolean
  def has_cookie_ops?(server) do
    not Enum.empty?(server.__meta__.cookie_ops)
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
    new_cookie_ops = Map.put(server.__meta__.cookie_ops, key, cookie_struct)
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
  Adds a session entry.

  Atom keys are automatically converted to string.

  ## Parameters

    * `server` - The server struct
    * `key` - The session entry name (atom or string)
    * `value` - The session entry value
  """
  @spec put_session(t(), atom | String.t(), any()) :: t()
  def put_session(server, key, value)

  def put_session(server, key, value) when is_atom(key) do
    put_session(server, Atom.to_string(key), value)
  end

  def put_session(server, key, value) when is_binary(key) do
    new_session = Map.put(server.session, key, value)

    new_session_ops = Map.put(server.__meta__.session_ops, key, {:put, value})
    new_meta = %{server.__meta__ | session_ops: new_session_ops}

    %{server | session: new_session, __meta__: new_meta}
  end

  # TODO: reconsider if this argument validation is needed once Elixir has static typing
  def put_session(_server, key, _value) do
    raise ArgumentError, "Session key must be an atom or a string, but received #{inspect(key)}"
  end
end
