defmodule HologramFeatureTests.ContentSecurityPolicyTest do
  use HologramFeatureTests.TestCase, async: true

  alias Hologram.Router.Helpers, as: RouterHelpers
  alias HologramFeatureTests.ContentSecurityPolicy.Page1
  alias HologramFeatureTests.ContentSecurityPolicy.Page2
  alias HologramFeatureTests.ContentSecurityPolicy.Page3
  alias HologramFeatureTestsWeb.Endpoint

  # Records each violation the page reports as an element naming the directive it broke, so a test
  # can wait for it like for any text. A violation is no JavaScript error, so the driver raises on
  # none.
  @record_violations """
  document.addEventListener("securitypolicyviolation", (event) => {
    const element = document.createElement("p");
    element.className = "violation";
    element.textContent = event.effectiveDirective;
    document.body.append(element);
  });
  """

  test "first load carries the policy with the document's nonce" do
    conn =
      :get
      |> Plug.Test.conn(RouterHelpers.page_path(Page1))
      |> Endpoint.call(Endpoint.init([]))

    [_full_match, csp_nonce] =
      Regex.run(~r'globalThis\.Hologram\.cspNonce = "([^"]+)";', conn.resp_body)

    assert Plug.Conn.get_resp_header(conn, "content-security-policy") == [
             "base-uri 'none'; form-action 'self'; frame-ancestors 'self'; img-src 'self' data:; " <>
               "object-src 'none'; require-trusted-types-for 'script'; " <>
               "script-src 'nonce-#{csp_nonce}' 'strict-dynamic' 'unsafe-inline' https:; " <>
               "trusted-types hologram default"
           ]

    assert conn.resp_body =~
             ~s'<script nonce="#{csp_nonce}" type="application/json" id="hologram-boot-data">'

    script_tags = Regex.scan(~r/<script[ >][^>]*>/, conn.resp_body)

    nonced_script_tags =
      Regex.scan(~r/<script nonce="#{Regex.escape(csp_nonce)}"[ >]/, conn.resp_body)

    assert script_tags != []
    assert length(nonced_script_tags) == length(script_tags)
  end

  feature "runs an inline script the template carries", %{session: session} do
    session
    |> visit(Page2)
    |> assert_text(css("#result"), "page 2 inline script ran")
  end

  # The script element is the client's own here, created through the runtime's Trusted Types
  # policy, which the document enforces, and carrying the document's nonce. The mark set before the
  # click survives it, so the page was navigated to rather than loaded, which would have the
  # browser run the script itself.
  feature "runs an inline script a navigated page carries", %{session: session} do
    nonce_matches = """
    const nonce = globalThis.Hologram.cspNonce;
    return nonce !== "" && document.querySelector("#page_3_script").nonce === nonce;
    """

    session
    |> visit(Page1)
    |> execute_script("window.notReloaded = true;")
    |> click(link("Page 3 link"))
    |> assert_page(Page3)
    |> assert_text(css("#result"), "page 3 inline script ran")
    |> assert_script_result("return window.notReloaded === true;", true)
    |> assert_script_result(nonce_matches, true)
  end

  # An attacker who gets markup into a page can't run code through it: an inline event handler
  # carries no nonce. The default Trusted Types policy is what lets the test write markup at all.
  feature "blocks an inline event handler injected as markup", %{session: session} do
    inject_markup = """
    trustedTypes.createPolicy("default", {createHTML: (html) => html});

    document.body.insertAdjacentHTML(
      "beforeend",
      `<img src="data:," onerror="document.getElementById('result').textContent = 'injected'">`
    );
    """

    session
    |> visit(Page1)
    |> execute_script(@record_violations <> inject_markup)
    |> assert_text(css(".violation"), "script-src-attr")
    |> assert_text(css("#result"), "none")
  end

  feature "evaluates JS interop code", %{session: session} do
    session
    |> visit(Page1)
    |> click(button("Evaluate code"))
    |> assert_text(css("#result"), "evaluated 21")
  end
end
