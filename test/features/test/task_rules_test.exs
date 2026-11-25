defmodule HologramFeatureTests.TaskRulesTest do
  # async: false - each test truncates the shared tables, and the held task has one global name.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.TaskRulesPage

  setup do
    truncate_every_entity_table()

    start_supervised!({Task.Supervisor, name: TaskRulesPage.TaskSupervisor})

    # A test that fails before letting the held task go would otherwise leave its name taken for the
    # next one.
    on_exit(fn ->
      case :global.whereis_name({TaskRulesPage, :held}) do
        :undefined ->
          :ok

        holder ->
          monitor = Process.monitor(holder)
          Process.exit(holder, :kill)

          receive do
            {:DOWN, ^monitor, :process, ^holder, _reason} -> :ok
          end

          :global.unregister_name({TaskRulesPage, :held})
      end
    end)

    author =
      %{email: "author@example.com"}
      |> User.new()
      |> DB.create!()

    %{email: "stranger@example.com"}
    |> User.new()
    |> DB.create!()

    memo =
      %{author_id: author.id, body: "private", pinned: true}
      |> Memo.new()
      |> DB.create!()

    {:ok, memo: memo}
  end

  defp click_and_expect(session, label, result) do
    session
    |> click(button(label))
    |> assert_text(css("#result"), result)
  end

  # Lets the held task read while no request is being served. Bandit clears the dictionary of the
  # connection's process after each request, so this is when that process holds nothing from one.
  defp release_held_between_requests do
    send(:global.whereis_name({TaskRulesPage, :held}), {:go, self()})

    assert_receive {:held_result, result, command_pid}, 10_000

    # Else the connection closed, and the task is refused because its caller ended, whether or not
    # the record survived.
    assert Process.alive?(command_pid)

    result
  end

  defp sign_in_stranger(session) do
    session
    |> visit(TaskRulesPage)
    |> click_and_expect("Sign in stranger", "signed_in_stranger")
  end

  defp sign_in_author(session) do
    session
    |> visit(TaskRulesPage)
    |> click_and_expect("Sign in author", "signed_in_author")
  end

  feature "refuses a signed-in user's Task a read it doesn't carry the user for", %{
    session: session
  } do
    session
    |> sign_in_stranger()
    |> click_and_expect("Bare read", "bare_read_refused")
  end

  feature "refuses a signed-out visitor's Task a read", %{session: session} do
    session
    |> visit(TaskRulesPage)
    |> click_and_expect("Bare read", "bare_read_refused")
  end

  feature "refuses a Task a change it doesn't carry the user for", %{
    memo: memo,
    session: session
  } do
    session
    |> sign_in_stranger()
    |> click_and_expect("Bare change", "bare_change_refused")

    assert DB.read(Memo, memo.id).pinned
  end

  feature "refuses a Task that outlives its request", %{session: session} do
    session
    |> sign_in_author()
    |> click_and_expect("Hold bare", "holding_bare")
    |> click_and_expect("Sign in stranger", "signed_in_stranger")
    |> click_and_expect("Release held", "released_refused")
  end

  feature "refuses a supervised task that reads after its caller's requests ended", %{
    session: session
  } do
    session
    |> sign_in_author()
    |> click_and_expect("Hold supervised", "holding_supervised")
    |> click_and_expect("Sign in stranger", "signed_in_stranger")

    assert release_held_between_requests() == "refused"
  end

  feature "gives a carried Task what the signed-in user may read", %{session: session} do
    session
    |> sign_in_author()
    |> click_and_expect("Carried read", "carried_read_visible")
  end

  feature "hides from a carried Task what the signed-in user may not read", %{session: session} do
    session
    |> sign_in_stranger()
    |> click_and_expect("Carried read", "carried_read_hidden")
  end

  feature "lets a carried Task make a change the signed-in user may make", %{
    memo: memo,
    session: session
  } do
    session
    |> sign_in_author()
    |> click_and_expect("Carried change", "carried_change_applied")

    refute DB.read(Memo, memo.id).pinned
  end

  feature "denies a carried Task a change the signed-in user may not make", %{
    memo: memo,
    session: session
  } do
    session
    |> sign_in_stranger()
    |> click_and_expect("Carried change", "carried_change_denied")

    assert DB.read(Memo, memo.id).pinned
  end

  feature "keeps a carried Task on its user during the next user's request", %{
    session: session
  } do
    session
    |> sign_in_author()
    |> click_and_expect("Hold carried", "holding_carried")
    |> click_and_expect("Sign in stranger", "signed_in_stranger")
    |> click_and_expect("Release held", "released_author_visible")
  end

  feature "lets a Task read past the rules by claiming trust", %{session: session} do
    session
    |> sign_in_stranger()
    |> click_and_expect("Trusted read", "trusted_read_visible")
  end
end
