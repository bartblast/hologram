defmodule HologramFeatureTestsWeb.Plugs.PhoenixReloadFrame do
  @moduledoc false

  # Adds Phoenix's live reload iframe to the end of the body of one page, the way Phoenix's live
  # reload plug adds it to every page in dev. The test env runs no Phoenix live reload, so this
  # stands in for it.

  import Plug.Conn

  @iframe ~s(<iframe hidden height="0" width="0" src="/phoenix/live_reload/frame"></iframe>)

  @spec init(keyword) :: keyword
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword) :: Plug.Conn.t()
  def call(%Plug.Conn{request_path: "/live-reload/3"} = conn, _opts) do
    register_before_send(conn, fn conn ->
      # Before the last </body>, as Phoenix's plug puts it.
      {head, [last]} =
        conn.resp_body
        |> IO.iodata_to_binary()
        |> String.split("</body>")
        |> Enum.split(-1)

      %{conn | resp_body: [Enum.intersperse(head, "</body>"), @iframe, "</body>" | last]}
    end)
  end

  def call(conn, _opts), do: conn
end
