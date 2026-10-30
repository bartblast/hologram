defmodule HologramFeatureTests.ContentSecurityPolicy.Page3 do
  use Hologram.Page

  route "/content-security-policy/3"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, "none")
  end

  def template do
    ~HOLO"""
    <p>
      Result: <strong id="result">{@result}</strong>
    </p>
    <script id="page_3_script">
      Hologram.dispatchAction("put_result", "page", \{result: "page 3 inline script ran"\});
    </script>
    """
  end

  def action(:put_result, params, component) do
    put_state(component, :result, params.result)
  end
end
