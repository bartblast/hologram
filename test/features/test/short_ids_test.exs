defmodule HologramFeatureTests.ShortIdsTest do
  # async: false - each test truncates the shared notice table.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias HologramFeatureTests.Entities.Notice
  alias HologramFeatureTests.ShortIds.Page1
  alias HologramFeatureTests.ShortIds.Page2
  alias Wallaby.Browser

  setup do
    truncate_entity_tables([Notice])

    :ok
  end

  feature "a link to a page with an id param carries the short id", %{session: session} do
    notice =
      %{title: "made_on_server"}
      |> Notice.new()
      |> DB.create!()

    assert notice.id =~ ~r/\A[0-9A-Za-z]{22}\z/

    session
    |> visit(Page1)
    |> click(link("Notice link"))
    |> assert_page(Page2, id: notice.id)
    |> assert_text(css("#id"), notice.id)
    |> assert_text(css("#title"), "made_on_server")

    assert current_path(session) == "/short-ids/2/#{notice.id}"
  end

  # The browser makes the id, shows the notice from its own database under it, and the server
  # takes the same id - so a fresh load of the page, which reads the param and the notice on the
  # server, shows it too.
  feature "an entity created in the browser has a short id the server accepts", %{
    session: session
  } do
    session
    |> visit(Page1)
    |> click(button("Create a notice"))
    |> assert_text(css("#title"), "made_in_browser")

    id = Browser.text(session, css("#id"))

    assert id =~ ~r/\A[0-9A-Za-z]{22}\z/

    assert_page(session, Page2, id: id)

    assert %Notice{title: "made_in_browser"} = await_server_notice(id)

    session
    |> visit(Page2, id: id)
    |> assert_text(css("#id"), id)
    |> assert_text(css("#title"), "made_in_browser")
  end

  defp await_server_notice(id) do
    Enum.reduce_while(1..100, nil, fn _attempt, _acc ->
      case DB.read(Notice, id) do
        nil ->
          Process.sleep(50)
          {:cont, nil}

        notice ->
          {:halt, notice}
      end
    end)
  end
end
