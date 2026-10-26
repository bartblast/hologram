defmodule HologramFeatureTests.Focus.Page7 do
  use Hologram.Page

  route "/focus/7"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :count, 0)
  end

  # The inline script runs while the page is parsed, before the runtime boots on
  # DOMContentLoaded, and moves focus the way a user who clicks before the page is interactive
  # would. The browser then skips its own autofocus, and the boot render must not claim it either.
  def template do
    ~HOLO"""
    <p>
      <input type="text" id="page_7_search" $focused={true} />
      <input type="text" id="page_7_other" />
    </p>
    <p>
      <button id="page_7_increment" $click="increment">Increment</button>
      Count: <strong id="page_7_count">{@count}</strong>
    </p>
    <script>
      {%raw}
        document.getElementById("page_7_other").focus();
      {/raw}
    </script>
    """
  end

  def action(:increment, _params, component) do
    put_state(component, :count, component.state.count + 1)
  end
end
