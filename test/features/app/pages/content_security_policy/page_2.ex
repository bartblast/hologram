defmodule HologramFeatureTests.ContentSecurityPolicy.Page2 do
  use Hologram.Page

  route "/content-security-policy/2"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, "none")
  end

  def template do
    ~HOLO"""
    <p>
      Result: <strong id="result">{@result}</strong>
    </p>
    <script id="page_2_script">
      Hologram.dispatchAction("put_result", "page", \{result: "page 2 inline script ran"\});
    </script>
    """
  end

  def action(:put_result, params, component) do
    put_state(component, :result, params.result)
  end
end
