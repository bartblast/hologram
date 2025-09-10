defmodule HologramFeatureTests.Security.Page4 do
  use Hologram.Page

  route "/security/4"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :show_div_2?, false)
  end

  def template do
    ~HOLO"""
    <p>
      Div #1 (rendered server-side):<br />
      <div id="div_1" class="abc {~s'"><script>window.xss1 = true</script><div class="'} xyz">Text</div>
    </p>

    {%if @show_div_2?}
      <p>
        Div #2 (rendered client-side):<br />
        <div id="div_2" class="abc {~s'"><script>window.xss2 = true</script><div class="'} xyz">Text</div>
      </p>
    {/if}

    <p>
      <button $click="show_div_2">Show div #2</button>
    </p>    
    """
  end

  def action(:show_div_2, _params, component) do
    put_state(component, :show_div_2?, true)
  end
end
