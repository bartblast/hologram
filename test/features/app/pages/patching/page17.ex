defmodule HologramFeatureTests.Patching.Page17 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/17"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, :banner?, false)
  end

  # A conditional ahead of a sibling that holds state the DOM keeps on its own, toggled by one
  # button. Page 11 asks whether such a sibling survives; this one asks whether what it was holding
  # survives with it, which is the stronger question: a node can be moved rather than rebuilt and
  # lose its state anyway, and a test that only compares node identity would call that a pass.
  #
  # The banner and the container are both divs, which is the shape that pairs wrongly when siblings
  # are matched by tag and position. Keys are what stop it, so this is the shape where their
  # absence would show.
  #
  # The field is uncontrolled and its selection is set from the test, so neither the value nor the
  # range it covers is anything a re-render could put back: both live only in the node.
  #
  # Each holder gets a panel of its own, because only the element right after the conditional is
  # the one a positional pairing gets wrong. The next sibling is matched from the other end of the
  # list and survives whatever happens, so a second holder sharing a panel would be testing
  # snabbdom's right-hand walk rather than anything about keys. The field is wrapped for the same
  # reason: the pairing needs a div to mistake for the banner, and an input is not one.
  #
  # The image is the one holder whose state is not its own: what it holds is a loaded resource, and
  # a rebuilt one loads again, from the cache if not from the network. The counter in the head is
  # what reports that, and it is registered there so that the image's first load is counted too.
  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <script>
          {%raw}
            window.__imageLoads = 0;

            document.addEventListener(
              "load",
              (event) => {
                if (event.target.tagName === "IMG") {
                  window.__imageLoads += 1;
                }
              },
              true,
            );
          {/raw}
        </script>
        <Runtime />
        <CommonLayoutStyles />
      </head>
      <body>
        <p>
          <button $click="toggle_banner">Toggle banner</button>
        </p>

        <div id="panel_scroll">
          {%if @banner?}
            <div class="banner">banner</div>
          {/if}
          <div id="feed" style="height: 40px; overflow: auto">
            <p style="height: 400px">tall enough to scroll</p>
          </div>
        </div>

        <div id="panel_select">
          {%if @banner?}
            <div class="banner">banner</div>
          {/if}
          <div class="keeper">
            <input type="text" id="field" />
          </div>
        </div>

        <div id="panel_image">
          {%if @banner?}
            <div class="banner">banner</div>
          {/if}
          <div class="keeper">
            <img id="photo" src="/images/sample.png" width="40" height="30" alt="sample" />
          </div>
        </div>

        <div id="result">{@banner?}</div>
      </body>
    </html>
    """
  end

  def action(:toggle_banner, _params, component) do
    put_state(component, :banner?, !component.state.banner?)
  end
end
