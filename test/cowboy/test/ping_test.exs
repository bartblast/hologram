defmodule HologramCowboyTests.PingTest do
  use HologramCowboyTests.TestCase, async: false

  alias HologramCowboyTests.PlainPage

  # The client pings on a 30 s interval, too slow to wait for, so the browser is asked to
  # send one now, the same HEAD request the client sends, and to write the status where
  # assert_text can see it.
  @script """
  fetch("/hologram/ping", {method: "HEAD"}).then((response) => {
    document.body.insertAdjacentHTML("beforeend", `<p id="ping">${response.status}</p>`);
  });
  """

  feature "the ping route answers", %{session: session} do
    session
    |> visit(PlainPage)
    |> execute_script(@script)
    |> assert_text(css("#ping"), "200")
  end
end
