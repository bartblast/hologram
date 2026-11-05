defmodule HologramFeatureTestsWeb.Plugs.ForeignNodes do
  @moduledoc false

  # Adds nodes to the head and body of the foreign nodes pages, the way other tools do: a dev
  # toolbar's plug appends its meta, style and script to the head, a browser extension adds nodes
  # at the start or in the middle. Each one sits next to a node the layout renders, a meta before
  # the layout's meta among them.

  import Plug.Conn

  @paths ["/foreign-nodes/1", "/foreign-nodes/2"]

  @insertions [
    {"<head>", ~s(<head><meta name="x-tool:first" content="1">)},
    {"</title>", ~s(</title><meta name="x-tool:middle" content="1">)},
    {"</head>",
     ~s(<meta name="x-tool:config" content="1">) <>
       ~s(<style id="x-tool-style">.x-tool {}</style>) <>
       "<script>globalThis.xToolRan = true;</script></head>"},
    {"<body>", ~s(<body><div id="x-tool-start"></div>)},
    {"</body>", ~s(<div id="x-tool-end"></div></body>)}
  ]

  @spec init(keyword) :: keyword
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword) :: Plug.Conn.t()
  def call(%Plug.Conn{request_path: path} = conn, _opts) when path in @paths do
    register_before_send(conn, fn conn ->
      html = IO.iodata_to_binary(conn.resp_body)

      resp_body =
        Enum.reduce(@insertions, html, fn {tag, replacement}, acc ->
          String.replace(acc, tag, replacement, global: false)
        end)

      %{conn | resp_body: resp_body}
    end)
  end

  def call(conn, _opts), do: conn
end
