defmodule HologramFeatureTests.Middleware.Page9 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Middleware.Page10
  alias HologramFeatureTests.Middleware.Page11
  alias HologramFeatureTests.Middleware.Page2
  alias HologramFeatureTests.Middleware.Page4

  route "/middleware/9"

  layout HologramFeatureTests.Components.DefaultLayout

  # Where the redirect tests navigate from, so that what a middleware answers is reached by
  # clicking rather than by visiting - a client-side navigation, which is the case that used to
  # land on the clicked page's path while showing the redirect target's content.
  #
  # The inline script counts its own runs, which is how the tests tell a client-side navigation
  # from a document load: a load runs it again and resets the count.
  def template do
    ~HOLO"""
    <h1>Middleware / Page 9</h1>

    <Link to={Page2}>Redirecting link</Link>
    <Link to={Page10}>Redirect chain link</Link>
    <Link to={Page11}>Non-page redirect link</Link>
    <Link to={Page4}>Denied link</Link>

    <p id="result">navigation origin</p>

    <script>
      {%raw}
        window.__documentLoads = (window.__documentLoads || 0) + 1;
      {/raw}
    </script>
    """
  end
end
