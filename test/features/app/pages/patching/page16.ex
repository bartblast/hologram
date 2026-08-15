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
  # The conditional is here so that a block, whose node count the client cannot know from the
  # markup alone, is part of what has to be adopted.
  #
  # The image is here because it is the symptom the issue was reported for: a recreated <img> loads
  # and decodes again, which is what flashes on a page carrying many of them. Its node is the one
  # that says whether that happens, since an element that is never rebuilt has nothing to re-fetch.
  #
  # The counter in the head is what proves it in the browser's own terms. Resource timing cannot:
  # a rebuilt image resolves from the memory cache and no second entry is recorded, so the count
  # reads the same either way. A load event does fire again, cache or not. The listener sits in the
  # head so that it is registered before the image below is parsed, which is the only placement
  # where the server's own load is guaranteed to be counted.
  #
  # The head's own nodes are stamped as well, because it is the one place where the render and the
  # markup genuinely differ: the runtime's scripts are gated on page_mounted?, so the server emits
  # them and the boot render does not name them. Adoption has to hold across that gap - the metas,
  # this script and the style stay the server's, while the scripts the render no longer names are
  # removed rather than rebuilt.
  #
  # The script also puts the page into the state the issue says gets lost - a focused field, a
  # selection within it, a scrolled container - and does it from here rather than from the test,
  # since only a script in the markup runs before the first patch. None of it is stamped: state is
  # a stronger claim than identity, because a node can survive and still lose it. Moving a live
  # element blurs it and can reset a scroll container, and a node that merely holds still says
  # nothing about whether it was moved.
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
          <button $click="increment">Increment</button>
        </p>

        <div id="kept">
          {%if @hint?}
            <p id="hint">hint</p>
          {/if}
          <input type="text" id="field" />
          <span id="marked">server text</span>
        </div>

        <img id="photo" src="/images/sample.png" width="40" height="30" alt="sample" />

        <div id="feed" style="height: 40px; overflow: auto">
          <p style="height: 400px">tall enough to scroll</p>
        </div>

        <div id="result">{@count}</div>

        <script>
          {%raw}
            window.__scriptRuns = (window.__scriptRuns || 0) + 1;

            document
              .querySelectorAll("#kept, #hint, #field, #marked, #result, #photo")
              .forEach((node) => {
                node.__fromServer = true;
              });

            Array.from(document.head.children).forEach((node) => {
              node.__fromServer = true;
            });

            // Block-scoped, so that a re-run redeclares nothing. A second top-level const is an
            // early error, which would throw before the counter above could report the re-run.
            {
              const field = document.getElementById("field");

              field.value = "server text";
              field.focus();
              field.setSelectionRange(2, 5);
            }

            document.getElementById("feed").scrollTop = 30;
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
