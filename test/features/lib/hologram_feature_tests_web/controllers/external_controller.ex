defmodule HologramFeatureTestsWeb.ExternalController do
  use HologramFeatureTestsWeb, :controller

  def index(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html>
      <head>
        <title>External Page</title>
      </head>
      <body>
        <h1>External Page</h1>
        <p>This is an external page for testing navigation.</p>
      </body>
    </html>
    """)
  end
end
