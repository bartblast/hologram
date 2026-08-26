defmodule HologramFeatureTestsWeb.Plugs.SlowPageBundle do
  @moduledoc false

  # A navigation puts the destination on screen as soon as the server describes it, and mounts it
  # once its bundle has arrived. Over a local loop the bundle arrives in milliseconds, so the
  # stretch in which the destination is displayed but not yet mounted is too short for a test to
  # act inside. This widens it on demand.
  #
  # Scoped by cookie, so concurrently running test files are unaffected, and idle unless a test
  # sets it.

  import Plug.Conn

  @cookie "hologram_page_bundle_delay_ms"

  @doc """
  Returns the name of the cookie carrying the delay, in milliseconds.
  """
  @spec cookie() :: String.t()
  def cookie, do: @cookie

  @spec init(keyword) :: keyword
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword) :: Plug.Conn.t()
  def call(%Plug.Conn{request_path: "/hologram/page-" <> _rest} = conn, _opts) do
    conn = fetch_cookies(conn)

    with delay_ms when is_binary(delay_ms) <- conn.cookies[@cookie],
         {delay_ms, ""} <- Integer.parse(delay_ms) do
      Process.sleep(delay_ms)
    end

    conn
  end

  def call(conn, _opts), do: conn
end
