defmodule HologramFeatureTests.Patching.Page16 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/16"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, count: 0, hint?: true)
  end

  # The page the client boots onto is already in the browser, so the first render has nothing to
  # build - it only has to take ownership of what the server sent. This page reports whether it
  # did.
  #
  # The inline script is the instrument. A script element runs when it is created, so if the first
  # patch rebuilds it rather than adopting it, the browser runs it a second time and the counter
  # reads 2. That is not only a probe: a page carrying an analytics snippet or a third-party embed
  # would fire it twice for real.
  #
  # It also stamps the nodes the server rendered, which is only trustworthy while the counter reads
  # 1 - a re-run would stamp whatever the patch had just built and report those as the server's.
  #
  # The conditional is here so a block, and the markers bracketing it, are part of what has to be
  # adopted.
  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
        <CommonLayoutStyles />
      </head>
      <body>
        <p>
          <button $click="increment">Increment</button>
        </p>

        <div id="kept">
          {%if @hint?}
            <p id="hint">hint</p>
          {/if}
          <input type="text" id="field" />
          <span id="marked">server text</span>
        </div>

        <div id="result">{@count}</div>

        <script>
          {%raw}
            window.__scriptRuns = (window.__scriptRuns || 0) + 1;

            document
              .querySelectorAll("#kept, #hint, #field, #marked, #result")
              .forEach((node) => {
                node.__fromServer = true;
              });
          {/raw}
        </script>
      </body>
    </html>
    """
  end

  def action(:increment, _params, component) do
    put_state(component, :count, component.state.count + 1)
  end
end
