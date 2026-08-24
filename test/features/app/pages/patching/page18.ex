defmodule HologramFeatureTests.Patching.Page18 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/18"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, count: 0)
  end

  # An HTML tag name has no case: the browser reads one back uppercase whatever the markup wrote,
  # so lowercasing what it says is how the client recognises the node it is describing. Inside
  # <svg> that stops being true. Those names keep the case the spec gives them, and the parser
  # corrects the markup's spelling to it, so the browser reports "linearGradient" here however the
  # template spelled it. An element named this way is the only kind whose name the two sides can
  # disagree about, and a disagreement means the first render rebuilds it instead of taking it
  # over - it and everything under it.
  #
  # The inline script is the instrument. It stamps the nodes the server rendered before the client
  # boots, so a node that still carries the stamp afterwards is the server's own rather than a
  # replacement built to look like it.
  #
  # The stamp is only trustworthy while the counter reads 1. A script element runs when it is
  # created, so a first render that rebuilt the whole page would run this one a second time and
  # stamp whatever the patch had just built, reporting those as the server's.
  #
  # The <svg> element is stamped alongside the gradient as a control. Its name is lowercase in
  # every namespace, so it is adopted whether or not the case bug is present: a run where both
  # fail is a broken page rather than this bug, and a run where only the gradient fails is the bug
  # itself.
  #
  # The button is here so the test can wait for a click to land. Without it the assertions would
  # pass against a page that had booted no further than the server's markup, which is the one
  # state where nothing has been rebuilt yet.
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

        <svg id="art" width="0" height="0">
          <defs>
            <linearGradient id="grad"><stop offset="0"></stop></linearGradient>
          </defs>
        </svg>

        <div id="result">{@count}</div>

        <script>
          {%raw}
            window.__scriptRuns = (window.__scriptRuns || 0) + 1;

            document.querySelectorAll("#art, #grad").forEach((node) => {
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
