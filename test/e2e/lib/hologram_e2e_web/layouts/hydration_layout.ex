defmodule HologramE2E.HydrationLayout do
  use Hologram.Layout

  def init(_params) do
    %{
      count: 200
    }
  end

  def template do
    ~H"""
    <!DOCTYPE html>
    <html>
      <head>
        <title>Hologram E2E</title>
        <Hologram.UI.Runtime />
      </head>
      <body>
        <button id="layout-button" on:click="increment">Increment in layout</button>
        <div id="layout-text">layout count = {@count}</div>
        <slot />
      </body>
    </html>
    """
  end

  def action(:increment, _params, state) do
    put(state, :count, state.count + 1)
  end
end
