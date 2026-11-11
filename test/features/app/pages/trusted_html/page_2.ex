defmodule HologramFeatureTests.TrustedHtml.Page2 do
  use Hologram.Page

  route "/trusted-html/2"

  layout HologramFeatureTests.Components.DefaultLayout

  state :content, :any

  def init(_params, component, _server) do
    put_state(
      component,
      :content,
      trust_html(
        ~s(<p class="navigated">Navigated <b>page</b></p><script>window.navigatedScriptRan = true;</script>)
      )
    )
  end

  def template do
    ~HOLO"""
    <div id="content">{@content}</div>
    """
  end
end
