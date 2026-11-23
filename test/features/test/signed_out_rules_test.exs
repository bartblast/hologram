defmodule HologramFeatureTests.SignedOutRulesTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Jobs.UpdateMemo
  alias HologramFeatureTests.SignedOutRulesPage

  setup do
    truncate_every_entity_table()

    memo =
      %{body: "private"}
      |> Memo.new()
      |> DB.create!()

    {:ok, memo: memo}
  end

  defp await_finished_job(attempts \\ 200)

  defp await_finished_job(0) do
    raise Wallaby.ExpectationNotMetError, "the job didn't finish"
  end

  defp await_finished_job(attempts) do
    case DB.read(UpdateMemo) do
      [%UpdateMemo{status: status} = job] when status in [:done, :failed] ->
        job

      _not_finished ->
        Process.sleep(50)
        await_finished_job(attempts - 1)
    end
  end

  # Only a signed-in session may read its own user row, so this proves the sign-in took.
  defp log_in(session) do
    session
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> click(button("Read self"))
    |> assert_text(css("#result"), "read_self_visible")
  end

  feature "keeps a private row out of a signed-out page's init", %{session: session} do
    session
    |> visit(SignedOutRulesPage)
    |> assert_text(css("#init_read"), "hidden")
  end

  feature "hides a private row from a signed-out command", %{session: session} do
    session
    |> visit(SignedOutRulesPage)
    |> click(button("Read private"))
    |> assert_text(css("#result"), "read_hidden")
  end

  feature "refuses a signed-out command's change to a private row", %{
    memo: memo,
    session: session
  } do
    session
    |> visit(SignedOutRulesPage)
    |> click(button("Change private"))
    |> assert_text(css("#result"), "change_refused")

    assert DB.read(Memo, memo.id).body == "private"
  end

  feature "runs a job a signed-out visitor created under the rules", %{
    memo: memo,
    session: session
  } do
    session
    |> visit(SignedOutRulesPage)
    |> click(button("Create job"))
    |> assert_text(css("#result"), "job_created")

    assert %UpdateMemo{actor_id: nil, status: :failed, error: error} = await_finished_job()
    assert error =~ "Hologram.AccessDeniedError"
    assert DB.read(Memo, memo.id).body == "private"
  end

  feature "lets a signed-out command read past the rules with trust", %{session: session} do
    session
    |> visit(SignedOutRulesPage)
    |> click(button("Trusted read"))
    |> assert_text(css("#result"), "trusted_read_visible")
  end

  feature "lets a signed-out command change a row past the rules with trust", %{
    memo: memo,
    session: session
  } do
    session
    |> visit(SignedOutRulesPage)
    |> click(button("Trusted change"))
    |> assert_text(css("#result"), "trusted_change_applied")

    assert DB.read(Memo, memo.id).body == "changed_by_server"
  end

  feature "hides a private row from a signed-in user it doesn't belong to", %{session: session} do
    session
    |> visit(SignedOutRulesPage)
    |> log_in()
    |> click(button("Read private"))
    |> assert_text(css("#result"), "read_hidden")
  end

  feature "refuses a signed-in user's change to a row it doesn't belong to", %{
    memo: memo,
    session: session
  } do
    session
    |> visit(SignedOutRulesPage)
    |> log_in()
    |> click(button("Change private"))
    |> assert_text(css("#result"), "change_refused")

    assert DB.read(Memo, memo.id).body == "private"
  end
end
