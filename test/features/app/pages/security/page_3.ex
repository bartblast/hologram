defmodule HologramFeatureTests.Security.Page3 do
  use Hologram.Page

  route "/security/3"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :show_script_3?, false)
  end

  def template do
    ~HOLO"""
    <p>
      Script #1 should be executed (window.xss1 = true)
      <script id="script_1">window.xss1 = true</script>
    </p>

    <p>
      Script #2 (rendered server-side) shouldn't be executed:<br />
      {~s'<script id="script_2">window.xss2 = true</script>'}
    </p>

    {%if @show_script_3?}
      <p>
        Script #3 (rendered client-side) shouldn't be executed:<br />
        {~s'<script id="script_3">window.xss3 = true</script>'}
      </p>
    {/if}

    <p>
      <button $click="show_script_3">Show script #3</button>
    </p>
    """
  end

  def action(:show_script_3, _params, component) do
    put_state(component, :show_script_3?, true)
  end
end
