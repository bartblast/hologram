defmodule HologramFeatureTests.Patching.Page19 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/19"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, :show?, false)
  end

  # HTML source carries no tag-name case: the tokenizer lowercases a name before anything else
  # sees it, and inside <svg> the parser then restores the spelling the SVG spec gives it. So the
  # lowercase spelling below is deliberate and means the same element as "linearGradient" would -
  # it is what the browser reads either way.
  #
  # Reading the markup is forgiving in a way that building an element is not: createElementNS is
  # handed a name and creates exactly that, so a client that was given the template's own spelling
  # would produce a node in the SVG namespace that is not an SVG element at all.
  #
  # The block is what forces the client to build rather than adopt. A page whose markup already
  # holds the gradient is adopted from what the server sent, with the parser's spelling already
  # applied, and the name the client would have built is never asked for - that is page 18, the
  # other half of this. Here the element is absent until the button opens the block, so the first
  # gradient that exists is one the client made.
  #
  # The rect is what a broken gradient would show: its fill points at the gradient by id, and a
  # node that is not an SVG element has nothing for the reference to resolve to.
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
          <button $click="show">Show</button>
        </p>

        {%if @show?}
          <svg id="art" width="10" height="10">
            <defs>
              <lineargradient id="grad"><stop offset="0"></stop></lineargradient>
            </defs>
            <rect id="shape" width="10" height="10" fill="url(#grad)"></rect>
          </svg>
        {/if}

        <div id="result">{@show?}</div>
      </body>
    </html>
    """
  end

  def action(:show, _params, component) do
    put_state(component, :show?, true)
  end
end
