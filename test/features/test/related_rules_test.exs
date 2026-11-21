defmodule HologramFeatureTests.RelatedRulesTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth
  alias Hologram.DB
  alias HologramFeatureTests.Entities.Bench
  alias HologramFeatureTests.Entities.Permit
  alias HologramFeatureTests.Entities.Tool
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.Entities.Workshop
  alias HologramFeatureTests.Policies.Page12

  # Each rule of a tool reads a workshop, a bench or a permit, which only the workshop's owner may
  # read, and the user owns none, so their browser holds none. The server reads the stored rows, so
  # the browser answers can? from the server's verdict on each tool it was sent: through a
  # condition on the workshop, a delegation to its update rule, a role held on the bench's
  # workshop, or an any over the tool's permits.
  #
  # Other tables reference the user table, so every table truncates with it.
  setup do
    truncate_every_entity_table()
  end

  # A second visit waits for the mount, so the assertion reads what the browser answered, not the
  # server's render. The tools it holds are asserted too, so a tool left out of the answer is one
  # the browser holds and answers no for.
  defp assert_on_visit(session, id, tools, labels) do
    session
    |> visit(Page12)
    |> assert_text(css("#tools"), tools)
    |> assert_text(css("##{id}"), labels)
  end

  # A visit waits for the mount, so what is asserted after it is the browser's answer.
  defp await_tools(session, labels) do
    session
    |> visit(Page12)
    |> await_local_fill()
    |> assert_text(css("#tools"), labels)
    |> mark_this_page_load()
  end

  defp create(entity_type, values) do
    values
    |> entity_type.new()
    |> DB.create!()
  end

  defp grant_editor(workshop) do
    user =
      User
      |> DB.read()
      |> Enum.find(&(&1.email == "editor@example.com"))

    Auth.grant_role(user, :editor, workshop)
  end

  defp log_in(session) do
    session
    |> visit(Page12)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
  end

  feature "lets the user read a tool in an open workshop they may not read", %{session: session} do
    create(Tool, %{label: "alpha", workshop_id: create(Workshop, %{}).id})
    create(Tool, %{label: "beta", workshop_id: create(Workshop, %{open: false}).id})

    session
    |> log_in()
    |> assert_on_visit("readable_tools", ~r/^alpha$/, ~r/^alpha$/)
  end

  feature "lets the user update a tool in a workshop that isn't archived", %{session: session} do
    create(Tool, %{label: "gamma", workshop_id: create(Workshop, %{}).id})
    create(Tool, %{label: "delta", workshop_id: create(Workshop, %{archived: true}).id})

    session
    |> log_in()
    |> assert_on_visit("updatable_tools", ~r/^delta,gamma$/, ~r/^gamma$/)
  end

  feature "lets the user delete a tool in a workshop they edit", %{session: session} do
    workshop = create(Workshop, %{})
    create(Tool, %{label: "epsilon", workshop_id: workshop.id})
    create(Tool, %{label: "zeta", workshop_id: create(Workshop, %{}).id})

    session = log_in(session)
    grant_editor(workshop)

    assert_on_visit(session, "deletable_tools", ~r/^epsilon,zeta$/, ~r/^epsilon$/)
  end

  feature "lets the user relabel a tool on a bench of a workshop they edit", %{session: session} do
    workshop = create(Workshop, %{archived: true})
    edited = create(Workshop, %{})

    create(Tool, %{
      bench_id: create(Bench, %{workshop_id: edited.id}).id,
      label: "eta",
      workshop_id: workshop.id
    })

    create(Tool, %{
      bench_id: create(Bench, %{workshop_id: create(Workshop, %{}).id}).id,
      label: "theta",
      workshop_id: workshop.id
    })

    session = log_in(session)
    grant_editor(edited)

    assert_on_visit(session, "relabelable_tools", ~r/^eta,theta$/, ~r/^eta$/)
  end

  feature "lets the user move a tool with an approved permit", %{session: session} do
    workshop = create(Workshop, %{archived: true})
    approved = create(Tool, %{label: "iota", workshop_id: workshop.id})
    unapproved = create(Tool, %{label: "kappa", workshop_id: workshop.id})
    create(Permit, %{approved: true, tool_id: approved.id})
    create(Permit, %{tool_id: unapproved.id})

    session
    |> log_in()
    |> assert_on_visit("movable_tools", ~r/^iota,kappa$/, ~r/^iota$/)
  end

  feature "stops letting the user update a tool when its workshop is archived on the stream", %{
    session: session
  } do
    workshop = create(Workshop, %{})
    create(Tool, %{label: "lambda", workshop_id: workshop.id})

    session =
      session
      |> log_in()
      |> await_tools(~r/^lambda$/)
      |> assert_text(css("#updatable_tools"), ~r/^lambda$/)

    DB.update!(Workshop, workshop.id, archived: true)

    # The workshop stays open, so the browser still holds the tool and answers no for it.
    session
    |> assert_text(css("#updatable_tools"), ~r/^$/)
    |> assert_text(css("#tools"), ~r/^lambda$/)
    |> assert_same_page_load()
  end

  feature "starts letting the user delete a tool when they're made an editor of its workshop on the stream",
          %{session: session} do
    workshop = create(Workshop, %{})
    create(Tool, %{label: "mu", workshop_id: workshop.id})

    session =
      session
      |> log_in()
      |> await_tools(~r/^mu$/)
      |> assert_text(css("#deletable_tools"), ~r/^$/)

    grant_editor(workshop)

    session
    |> assert_text(css("#deletable_tools"), ~r/^mu$/)
    |> assert_same_page_load()
  end
end
