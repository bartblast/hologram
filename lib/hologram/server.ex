defmodule Hologram.Server do
  alias Hologram.Component.Action

  defmodule Cookie do
    @moduledoc """
    Represents a cookie to be set in the client's browser.
    """

    defstruct value: nil,
              domain: nil,
              http_only: true,
              max_age: nil,
              path: nil,
              same_site: :lax,
              secure: true,
              __meta__: %{node: nil, source: :server, timestamp: nil}

    @type t :: %__MODULE__{
            value: any(),
            domain: String.t() | nil | :unknown,
            http_only: boolean() | :unknown,
            max_age: integer() | nil | :unknown,
            path: String.t() | nil | :unknown,
            same_site: :lax | :none | :strict | :unknown,
            secure: boolean() | :unknown,
            __meta__: %{node: node | nil, source: :client | :server, timestamp: integer | nil}
          }
  end

  defstruct cookies: %{}, next_action: nil, session: %{}

  @type t :: %__MODULE__{
          cookies: %{String.t() => Cookie.t()},
          next_action: Action.t() | nil,
          session: %{atom => any}
        }

  @doc """
  Returns the current system time in microseconds since the Unix epoch.
  """
  @callback timestamp() :: non_neg_integer

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
      %Hologram.Server{cookies: %{"user_id" => %Hologram.Server.Cookie{value: 123, domain: nil, http_only: true, max_age: nil, path: nil, same_site: :lax, secure: true}}}

      iex> server = %Hologram.Server{}
      iex> put_cookie(server, "theme", "dark", secure: false, path: "/")
      %Hologram.Server{cookies: %{"theme" => %Hologram.Server.Cookie{value: "dark", domain: nil, http_only: true, max_age: nil, path: "/", same_site: :lax, secure: false}}}
  """
  @spec put_cookie(t(), String.t(), any(), keyword()) :: t()
  def put_cookie(server, key, value, opts \\ [])

  def put_cookie(server, key, value, opts) when is_binary(key) do
    attrs =
      opts
      |> Keyword.put(:value, value)
      |> Keyword.put(:__meta__, %{
        node: node(),
        source: :server,
        timestamp: impl().timestamp()
      })

    cookie = struct!(Cookie, attrs)

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
