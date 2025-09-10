defmodule HologramFeatureTests.Security.Page3 do
  use Hologram.Page

  route "/security/3"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :show_script_4?, false)
  end

  def template do
    ~HOLO"""
    <p>
      Script #1 should be executed (window.xss1 = true)
      <script id="script_1">window.xss1 = true</script>
    </p>

    <p>
      Script #2 (rendered server-side) shouldn't be executed:<br />
      &lt;script id=&quot;script_2&quot;&gt;window.xss2 = true&lt;/script&gt;
    </p>    

    <p>
      Script #3 (rendered server-side) shouldn't be executed:<br />
      {~s'<script id="script_3">window.xss3 = true</script>'}
    </p>

    {%if @show_script_4?}
      <p>
        Script #4 (rendered client-side) shouldn't be executed:<br />
        {~s'<script id="script_4">window.xss4 = true</script>'}
      </p>
    {/if}

    <p>
      <button $click="show_script_4">Show script #4</button>
    </p>
    """
  end

  def action(:show_script_4, _params, component) do
    put_state(component, :show_script_4?, true)
  end
end
