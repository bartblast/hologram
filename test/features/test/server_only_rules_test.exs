defmodule HologramFeatureTests.ServerOnlyRulesTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias HologramFeatureTests.Entities.Inspection
  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.ProjectMember
  alias HologramFeatureTests.Entities.Report
  alias HologramFeatureTests.Entities.ReportNote
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.Policies.Page10

  # Each read rule here reads a server-only attribute, a value the server never sends to a browser.
  # The server reads the stored value, so it sends only the rows the rule admits. The browser can't
  # read the value, so it answers can? from the server's verdict on each row it was sent.
  #
  # The memo, note, project member and role grant tables reference the user table, so they truncate
  # with it.
  setup do
    truncate_entity_tables([
      Inspection,
      Memo,
      Note,
      ProjectMember,
      Report,
      ReportNote,
      RoleGrant,
      User
    ])
  end

  defp create_note(body, report) do
    %{body: body, report_id: report.id}
    |> ReportNote.new()
    |> DB.create!()
  end

  defp create_report(title, reviewed) do
    %{reviewed: reviewed, title: title}
    |> Report.new()
    |> DB.create!()
  end

  defp log_in(session) do
    session
    |> visit(Page10)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
  end

  feature "lets the user read a reviewed report held when the page loads", %{session: session} do
    create_report("alpha", true)
    create_report("beta", false)

    # A second visit waits for the mount, so the assertion reads what the browser answered, not the
    # server's render.
    session
    |> log_in()
    |> visit(Page10)
    |> assert_text(css("#readable_reports"), ~r/^alpha$/)
  end

  feature "lets the user read a reviewed report arriving on the stream", %{session: session} do
    session
    |> log_in()
    |> reload()
    |> assert_text(css("#readable_reports"), ~r/^$/)
    |> mark_this_page_load()

    create_report("gamma", true)

    session
    |> assert_text(css("#readable_reports"), ~r/^gamma$/)
    |> assert_same_page_load()
  end

  feature "lets the user read an inspection with a date arriving on the stream", %{
    session: session
  } do
    session
    |> log_in()
    |> reload()
    |> assert_text(css("#readable_inspections"), ~r/^$/)
    |> mark_this_page_load()

    %{passed_on: ~D[2026-11-15], title: "delta"}
    |> Inspection.new()
    |> DB.create!()

    session
    |> assert_text(css("#readable_inspections"), ~r/^delta$/)
    |> assert_same_page_load()
  end

  # The note's update rule asks the report's read rule, so the browser answers it from the
  # server's verdict on the report. A note on an unreviewed report is sent too, but its report
  # isn't, so the browser can't decide that check and refuses it.
  feature "lets the user edit a note on a reviewed report arriving on the stream", %{
    session: session
  } do
    session
    |> log_in()
    |> reload()
    |> assert_text(css("#editable_notes"), ~r/^$/)
    |> mark_this_page_load()

    create_note("eta", create_report("theta", false))
    create_note("zeta", create_report("epsilon", true))

    session
    |> assert_text(css("#editable_notes"), ~r/^zeta$/)
    |> assert_same_page_load()
  end
end
