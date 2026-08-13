defmodule HologramClusterTestsWeb.ExternalController do
  use HologramClusterTestsWeb, :controller

  # A page outside Hologram, so a test can hold a document (e.g. to set cookies on its
  # browser) without starting an SSE connection.
  def index(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html>
      <head>
        <title>External Page</title>
      </head>
      <body>
        <h1>External Page</h1>
      </body>
    </html>
    """)
  end
end
