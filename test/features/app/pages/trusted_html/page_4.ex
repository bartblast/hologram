defmodule HologramFeatureTests.TrustedHtml.Page4 do
  use Hologram.Page

  route "/trusted-html/4"

  layout HologramFeatureTests.Components.DefaultLayout

  state :content, :any

  def init(_params, component, _server) do
    put_state(component, :content, trust_html("<b>original</b>"))
  end

  # The script stands for a browser extension changing the page before Hologram starts, and records
  # the warnings Hologram logs. It runs while the page parses.
  def template do
    ~HOLO"""
    <div id="content">{@content}</div>
    <script>
      window.trustedHtmlWarnings = [];
      const warn = console.warn;
      console.warn = (...args) => \{ window.trustedHtmlWarnings.push(args.join(" ")); warn(...args); \};
      document.querySelector("#content b").textContent = "changed";
    </script>
    <button $click="replace_content">Replace content</button>
    """
  end

  def action(:replace_content, _params, component) do
    put_state(component, :content, trust_html("<i>replaced</i>"))
  end
end
