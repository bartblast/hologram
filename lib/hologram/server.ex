defmodule Hologram.Server do
  alias Hologram.Component.Action
  alias Hologram.Router.Helpers, as: RouterHelpers
  alias Hologram.Runtime.Cookie
  alias Hologram.Runtime.PlugConnUtils
  alias Hologram.Runtime.Session
  alias Hologram.Server.Broadcast
  alias Hologram.Server.Metadata
  alias Hologram.Server.Status

  defstruct broadcasts: [],
            cid: nil,
            cookies: %{},
            host: nil,
            instance_id: nil,
            ip: nil,
            method: nil,
            next_action: nil,
            path: nil,
            port: nil,
            query: %{},
            raw_query: nil,
            request_headers: %{},
            response_body: nil,
            response_headers: %{},
            scheme: nil,
            session: %{},
            session_id: nil,
            status: nil,
            subscriptions: [],
            user_id: nil,
            __meta__: %Metadata{}

  @type identity_id :: String.t() | integer | atom

  @type t :: %__MODULE__{
          broadcasts: [Broadcast.t()],
          cid: String.t() | nil,
          cookies: %{String.t() => any()},
          host: String.t() | nil,
          instance_id: String.t() | nil,
          ip: String.t() | nil,
          method: atom() | nil,
          next_action: Action.t() | nil,
          path: String.t() | nil,
          port: :inet.port_number() | nil,
          query: %{String.t() => String.t()},
          raw_query: String.t() | nil,
          request_headers: %{String.t() => String.t()},
          response_body: iodata() | nil,
          response_headers: %{String.t() => String.t()},
          scheme: :http | :https | nil,
          session: %{atom => any},
          session_id: identity_id | nil,
          status: pos_integer() | nil,
          subscriptions: [tuple],
          user_id: identity_id | nil,
          __meta__: Metadata.t()
        }

  @doc """
  Appends a value to a response header, keeping any existing value.

  The header name is downcased. If the header already has a value, the new value is
  appended after a comma. Use `put_response_header/3` to replace instead of append.

  ## Parameters

    * `server` - The server struct
    * `name` - The header name (string)
    * `value` - The header value to append (string)
  """
  @spec append_response_header(t(), String.t(), String.t()) :: t()
  def append_response_header(server, name, value)

  def append_response_header(server, name, value) when is_binary(name) and is_binary(value) do
    key = String.downcase(name)
    ensure_not_cookie_header!(key)

    new_value =
      case Map.fetch(server.response_headers, key) do
        {:ok, existing} -> existing <> ", " <> value
        :error -> value
      end

    %{server | response_headers: Map.put(server.response_headers, key, new_value)}
  end

  # TODO: reconsider if this argument validation is needed once Elixir has static typing
  def append_response_header(_server, name, value) do
    raise ArgumentError,
          "Response header name and value must be strings, but received #{inspect(name)} and #{inspect(value)}"
  end

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
  Removes a response header from the server struct so it will not be sent.

  The header name is downcased to match how headers are stored. Removing a header
  that is not present is a no-op.

  ## Parameters

    * `server` - The server struct
    * `name` - The header name (string)
  """
  @spec delete_response_header(t(), String.t()) :: t()
  def delete_response_header(server, name)

  def delete_response_header(server, name) when is_binary(name) do
    key = String.downcase(name)
    ensure_not_cookie_header!(key)

    new_response_headers = Map.delete(server.response_headers, key)
    %{server | response_headers: new_response_headers}
  end

  # TODO: reconsider if this argument validation is needed once Elixir has static typing
  def delete_response_header(_server, name) do
    raise ArgumentError, "Response header name must be a string, but received #{inspect(name)}"
  end

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

  Populates the request fields (`method`, `scheme`, `host`, `port`, `path`, `query`,
  `raw_query`, `ip`, `request_headers`) and the identity fields. The `cookie` request
  header is dropped from `request_headers` since cookies are exposed via the cookie
  functions, and a request header sent multiple times is comma-joined.

  Excludes "hologram_session" cookie. Populates `session_id` and `user_id`
  from the Phoenix session (each `nil` when the underlying entry is absent),
  and strips those Hologram-managed keys from the `session` map so it
  contains only application-level entries.
  """
  @spec from(Plug.Conn.t()) :: t
  def from(%Plug.Conn{} = conn) do
    %__MODULE__{
      cookies: PlugConnUtils.extract_cookies(conn),
      host: conn.host,
      ip: build_request_ip(conn.remote_ip),
      method: build_request_method(conn.method),
      path: conn.request_path,
      port: conn.port,
      query: URI.decode_query(conn.query_string),
      raw_query: conn.query_string,
      request_headers: build_request_headers(conn.req_headers),
      scheme: conn.scheme,
      session: Session.get_session(conn),
      session_id: Session.get_session_id(conn),
      user_id: Session.get_user_id(conn)
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
  Retrieves a request header value by name from the server struct.

  The header name is downcased to match how request headers are stored. Returns the
  value associated with the name, or the default if the header is not present.

  ## Parameters

    * `server` - The server struct
    * `name` - The header name (string)
    * `default` - The value to return if the header is not present (default: `nil`)
  """
  @spec get_request_header(t(), String.t(), any()) :: any()
  def get_request_header(server, name, default \\ nil)

  def get_request_header(server, name, default) when is_binary(name) do
    key = String.downcase(name)
    ensure_not_cookie_header!(key)

    Map.get(server.request_headers, key, default)
  end

  # TODO: reconsider if this argument validation is needed once Elixir has static typing
  def get_request_header(_server, name, _default) do
    raise ArgumentError, "Request header name must be a string, but received #{inspect(name)}"
  end

  @doc """
  Retrieves a response header value by name from the server struct.

  The header name is downcased to match how response headers are stored. Returns the
  value associated with the name, or the default if the header is not present.

  ## Parameters

    * `server` - The server struct
    * `name` - The header name (string)
    * `default` - The value to return if the header is not present (default: `nil`)
  """
  @spec get_response_header(t(), String.t(), any()) :: any()
  def get_response_header(server, name, default \\ nil)

  def get_response_header(server, name, default) when is_binary(name) do
    key = String.downcase(name)
    ensure_not_cookie_header!(key)

    Map.get(server.response_headers, key, default)
  end

  # TODO: reconsider if this argument validation is needed once Elixir has static typing
  def get_response_header(_server, name, _default) do
    raise ArgumentError, "Response header name must be a string, but received #{inspect(name)}"
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
  Sets a temporary (302) redirect to the given target, marking the response as terminal.

  The target is either a URL string, used as-is, or a page module, resolved to its path.
  For a page with params, use `put_redirect/3`. For a different status code, follow with
  `put_status/2`.

  ## Parameters

    * `server` - The server struct
    * `target` - A URL string or a page module
  """
  @spec put_redirect(t(), String.t() | module()) :: t()
  def put_redirect(server, url) when is_binary(url) do
    server
    |> put_status(302)
    |> put_response_header("location", url)
  end

  def put_redirect(server, page_module) when is_atom(page_module) do
    put_redirect(server, RouterHelpers.page_path(page_module))
  end

  # TODO: reconsider if this argument validation is needed once Elixir has static typing
  def put_redirect(_server, target) do
    raise ArgumentError,
          "Redirect target must be a URL string or a page module, but received #{inspect(target)}"
  end

  @doc """
  Sets a temporary (302) redirect to the given page module with params, marking the
  response as terminal.

  For a different status code, follow with `put_status/2`.

  ## Parameters

    * `server` - The server struct
    * `page_module` - The target page module
    * `params` - Page params (keyword list or map)
  """
  @spec put_redirect(t(), module(), keyword() | map()) :: t()
  def put_redirect(server, page_module, params) when is_atom(page_module) do
    put_redirect(server, RouterHelpers.page_path(page_module, params))
  end

  # TODO: reconsider if this argument validation is needed once Elixir has static typing
  def put_redirect(_server, page_module, _params) do
    raise ArgumentError,
          "Redirect params are only supported with a page module, but received #{inspect(page_module)}"
  end

  @doc """
  Sets a custom response body to be sent to the client.

  The body is iodata (a binary or an iolist). Combine with `put_status/2` to build a
  custom response (the status is what marks the response as terminal and skips the
  handler).

  ## Parameters

    * `server` - The server struct
    * `body` - The response body (iodata)
  """
  @spec put_response_body(t(), iodata()) :: t()
  def put_response_body(server, body)

  def put_response_body(server, body) when is_binary(body) or is_list(body) do
    %{server | response_body: body}
  end

  # TODO: reconsider if this argument validation is needed once Elixir has static typing
  def put_response_body(_server, body) do
    raise ArgumentError,
          "Response body must be iodata (a binary or an iolist), but received #{inspect(body)}"
  end

  @doc """
  Sets a response header to be sent to the client, replacing any existing value for the name.

  The header name is downcased, so names are case-insensitive and a later put
  overwrites an earlier one regardless of case.

  ## Parameters

    * `server` - The server struct
    * `name` - The header name (string)
    * `value` - The header value (string)
  """
  @spec put_response_header(t(), String.t(), String.t()) :: t()
  def put_response_header(server, name, value)

  def put_response_header(server, name, value) when is_binary(name) and is_binary(value) do
    key = String.downcase(name)
    ensure_not_cookie_header!(key)

    new_response_headers = Map.put(server.response_headers, key, value)
    %{server | response_headers: new_response_headers}
  end

  # TODO: reconsider if this argument validation is needed once Elixir has static typing
  def put_response_header(_server, name, value) do
    raise ArgumentError,
          "Response header name and value must be strings, but received #{inspect(name)} and #{inspect(value)}"
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

  @doc """
  Sets the response status, marking the response as terminal so the handler is skipped.

  Accepts an integer status code in the `100..599` range (e.g. `403`) or an atom
  alias (e.g. `:forbidden`), which is resolved to its numeric code. Raises for an
  unknown alias or an out-of-range code.

  ## Parameters

    * `server` - The server struct
    * `status` - The response status (integer code or atom alias)

  ## Examples

      iex> server = %Hologram.Server{}
      iex> put_status(server, 404)
      %Hologram.Server{status: 404}

      iex> server = %Hologram.Server{}
      iex> put_status(server, :not_found)
      %Hologram.Server{status: 404}
  """
  @spec put_status(t(), pos_integer() | atom()) :: t()
  def put_status(server, status)

  def put_status(server, status) when is_integer(status) and status in 100..599 do
    %{server | status: status}
  end

  def put_status(server, status) when is_atom(status) do
    %{server | status: Status.code(status)}
  end

  # TODO: reconsider if this argument validation is needed once Elixir has static typing
  def put_status(_server, status) do
    raise ArgumentError,
          "Response status must be an HTTP status code (100..599) or a status atom alias, but received #{inspect(status)}"
  end

  defp build_request_headers(req_headers) do
    req_headers
    |> Enum.reject(fn {name, _value} -> name == "cookie" end)
    |> Enum.reduce(%{}, fn {name, value}, acc ->
      Map.update(acc, name, value, &(&1 <> ", " <> value))
    end)
  end

  defp build_request_ip(ip) do
    ip
    |> :inet.ntoa()
    |> List.to_string()
  end

  defp build_request_method(method) do
    method
    |> String.downcase()
    |> String.to_existing_atom()
  end

  defp ensure_not_cookie_header!(name) when name in ["cookie", "set-cookie"] do
    raise ArgumentError,
          "#{name} is managed by the cookie functions (put_cookie, get_cookie, delete_cookie), not the header helpers"
  end

  defp ensure_not_cookie_header!(_name), do: :ok
end
