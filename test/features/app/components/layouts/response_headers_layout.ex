defmodule HologramFeatureTests.Components.ResponseHeadersLayout do
  use Hologram.Component

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  # The headers of a navigation's or a command's response are read by the runtime and shown nowhere,
  # so the layout records them where a test can read them. They are keyed by path, because other
  # requests, like the SSE handshake and the ping, follow the one under test.
  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
        <CommonLayoutStyles />
      </head>
      <body>
        <slot />
        <script>
          {%raw}
            if (!window.__responseHeaders) {
              window.__responseHeaders = {};
              const originalFetch = window.fetch;

              window.fetch = async (input, init) => {
                const response = await originalFetch(input, init);
                const path = new URL(input, window.location.href).pathname;
                window.__responseHeaders[path] = Object.fromEntries(response.headers);
                return response;
              };
            }
          {/raw}
        </script>
      </body>
    </html>
    """
  end
end
