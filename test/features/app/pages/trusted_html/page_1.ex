defmodule HologramFeatureTests.TrustedHtml.Page1 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.TrustedHtml.Page2

  route "/trusted-html/1"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      content:
        trust_html(
          ~s(<p class="trusted">Hello <strong>world</strong></p><script>window.trustedScriptRan = true;</script>)
        ),
      direct_rows: trust_html("<tr><td>direct row 1</td></tr>"),
      malformed: trust_html(~s(<div class="unclosed"><em>open</section>)),
      rows: trust_html("<tr><td>row 1</td></tr>")
    )
  end

  # The script records the warnings Hologram logs, so a test can check a page that matches what its
  # trusted HTML parses to logs none. It runs while the page parses, before Hologram starts.
  def template do
    ~HOLO"""
    <script>
      window.trustedHtmlWarnings = [];
      const warn = console.warn;
      console.warn = (...args) => \{ window.trustedHtmlWarnings.push(args.join(" ")); warn(...args); \};
    </script>
    <div id="content">{@content}</div>
    <div id="malformed">{@malformed}</div>
    <p id="after_malformed">after</p>
    <table id="rows_table"><tbody id="rows">{@rows}</tbody></table>
    <table id="direct_table">{@direct_rows}</table>
    <p>
      <button $click="replace_content">Replace content</button>
      <button $click="add_row">Add row</button>
      <button $click="add_direct_row">Add direct row</button>
    </p>
    <p>
      <Link to={Page2}>Page 2 link</Link>
    </p>
    """
  end

  def action(:add_direct_row, _params, component) do
    put_state(
      component,
      :direct_rows,
      trust_html("<tr><td>direct row 1</td></tr><tr><td>direct row 2</td></tr>")
    )
  end

  def action(:add_row, _params, component) do
    put_state(
      component,
      :rows,
      trust_html(["<tr><td>row 1</td></tr>", "<tr><td>row 2</td></tr>"])
    )
  end

  def action(:replace_content, _params, component) do
    put_state(
      component,
      :content,
      trust_html(
        ~s(<p class="replaced">Replaced <em>content</em></p><script>window.replacedScriptRan = true;</script>)
      )
    )
  end
end
