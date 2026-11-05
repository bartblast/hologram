defmodule HologramFeatureTests.TrustedHtml.Page3 do
  use Hologram.Page

  route "/trusted-html/3"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :content, trust_html("<div>block</div>"))
  end

  def template do
    ~HOLO"""
    <p>{@content}</p>
    """
  end
end
