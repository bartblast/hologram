defmodule HologramFeatureTests.PoliciesTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Booking
  alias HologramFeatureTests.Entities.Cabin
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Folder
  alias HologramFeatureTests.Entities.Leg
  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.Ship
  alias HologramFeatureTests.Entities.Stop
  alias HologramFeatureTests.Entities.Trip
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.Policies.Page2
  alias HologramFeatureTests.Policies.Page3
  alias HologramFeatureTests.Policies.Page5
  alias HologramFeatureTests.Policies.Page6
  alias HologramFeatureTests.Policies.Page7
  alias HologramFeatureTests.PoliciesPage
  alias HologramFeatureTests.Roles.Admin

  # The tables truncate in one statement: the memo, note and role grant tables' foreign keys to the
  # user table, the stop table's to the trip table, the leg table's to the stop table and the cabin
  # table's to the ship table make Postgres reject truncating the referenced table alone.
  setup do
    tables =
      Enum.map_join(
        [Booking, Cabin, Document, Folder, Leg, Memo, Note, RoleGrant, Ship, Stop, Trip, User],
        ", ",
        fn entity_type ->
          ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
        end
      )

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  # Three trips, one archived, each with a stop and a leg on it. Each feature makes the session user
  # an editor of the archived trip and the own trip, so a refusal on the archived one comes from the
  # trip being archived - its update rule for a new leg, the rename rule's condition for a rename -
  # and a refusal on the other trip from the role it does not hold there.
  defp seed_legs do
    Map.new(["archived", "other", "own"], fn prefix ->
      trip =
        %{archived: prefix == "archived", name: "#{prefix}_trip"}
        |> Trip.new()
        |> DB.create!()

      stop =
        %{name: "#{prefix}_stop", trip_id: trip.id}
        |> Stop.new()
        |> DB.create!()

      %{name: "#{prefix}_leg", stop_id: stop.id}
      |> Leg.new()
      |> DB.create!()

      {"#{prefix}_trip", trip}
    end)
  end

  # Two ships, each with a cabin. Each feature makes the session user the captain of the own ship
  # alone, so the other cabin stays out for want of the role.
  defp seed_ships do
    Map.new(["other", "own"], fn prefix ->
      ship =
        %{name: "#{prefix}_ship"}
        |> Ship.new()
        |> DB.create!()

      %{name: "#{prefix}_cabin", ship_id: ship.id}
      |> Cabin.new()
      |> DB.create!()

      {"#{prefix}_ship", ship}
    end)
  end

  defp seed_trips do
    Map.new(["archived_trip", "other_trip", "own_trip"], fn name ->
      trip =
        %{archived: name == "archived_trip", name: name}
        |> Trip.new()
        |> DB.create!()

      {name, trip}
    end)
  end

  defp session_user do
    User
    |> DB.read()
    |> Enum.find(&(&1.email == "session@example.com"))
  end

  feature "renders only unconditionally readable rows for an anonymous session", %{
    session: session
  } do
    %{public: true, title: "public_document"}
    |> Document.new()
    |> DB.create!()

    %{title: "private_document"}
    |> Document.new()
    |> DB.create!()

    session
    |> visit(PoliciesPage)
    |> assert_text(css("#documents"), "public_document")
    |> refute_has(css("#documents", text: "private_document"))
    |> assert_text(css("#session_user"), "anonymous")
  end

  feature "renders an included row only when the session may read it", %{session: session} do
    public_folder =
      %{name: "shared_folder", public: true}
      |> Folder.new()
      |> DB.create!()

    private_folder =
      %{name: "locked_folder"}
      |> Folder.new()
      |> DB.create!()

    %{folder_id: public_folder.id, public: true, title: "filed_document"}
    |> Document.new()
    |> DB.create!()

    %{folder_id: private_folder.id, public: true, title: "secret_document"}
    |> Document.new()
    |> DB.create!()

    session
    |> visit(PoliciesPage)
    |> assert_text(css("#documents"), "filed_document,secret_document")
    |> assert_text(css("#folders"), "shared_folder,none")
  end

  # The page is reloaded rather than revisited: Wallaby navigates to the URL the browser
  # already holds, which it treats as a no-op, so the row created in between would never
  # reach a render.
  feature "renders a row the session user created, through its creator role grant", %{
    session: session
  } do
    session
    |> visit(PoliciesPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> click(button("Create own document"))
    |> assert_text(css("#result"), "created_own_document")
    |> reload()
    |> assert_text(css("#documents"), "own_document")
    |> assert_text(css("#session_user"), "session@example.com")
  end

  feature "grants a role on a resource the session user manages", %{session: session} do
    session
    |> visit(PoliciesPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> click(button("Grant editor"))
    |> assert_text(css("#result"), "grant_editor_true")
  end

  # The document is created from the test process so nobody is its creator, and the session
  # user is then made its editor - a role that may not hand out the one above it.
  feature "refuses a role above the acting user's own", %{session: session} do
    session =
      session
      |> visit(PoliciesPage)
      |> click(button("Log in"))
      |> assert_text(css("#result"), "logged_in")

    document =
      %{title: "escalation_document"}
      |> Document.new()
      |> DB.create!()

    Auth.grant_role(session_user(), :editor, document)

    session
    |> click(button("Grant owner as editor"))
    |> assert_text(css("#result"), "grant_owner_as_editor_refused")
  end

  # The global role is granted from the test process (trusted), and the document is created
  # there too, so the session user holds nothing on it - what qualifies them is app-wide.
  feature "grants as a global admin on a document it holds no role on", %{session: session} do
    session =
      session
      |> visit(PoliciesPage)
      |> click(button("Log in"))
      |> assert_text(css("#result"), "logged_in")

    %{title: "admin_document"}
    |> Document.new()
    |> DB.create!()

    Auth.grant_role(session_user(), Admin)

    session
    |> click(button("Admin grants editor"))
    |> assert_text(css("#result"), "admin_grants_editor_granted_1")
  end

  feature "reads every row on the server's authority", %{session: session} do
    %{title: "hidden_document"}
    |> Document.new()
    |> DB.create!()

    %{public: true, title: "public_document"}
    |> Document.new()
    |> DB.create!()

    session
    |> visit(PoliciesPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> click(button("Read documents as server"))
    |> assert_text(css("#result"), "read_as_server_hidden_document,public_document")
  end

  feature "reads only the rows the session user may read", %{session: session} do
    %{title: "hidden_document"}
    |> Document.new()
    |> DB.create!()

    %{public: true, title: "public_document"}
    |> Document.new()
    |> DB.create!()

    session
    |> visit(PoliciesPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> click(button("Read documents as user"))
    |> assert_text(css("#result"), "read_as_user_public_document")
  end

  feature "revokes a role it granted", %{session: session} do
    session
    |> visit(PoliciesPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> click(button("Revoke editor"))
    |> assert_text(css("#result"), "revoke_editor_false")
  end

  # A visitor reads only through the alternative naming nobody, and may pin only through the
  # unpinned one - the pinned memo has no author, and a visitor never equals a missing author.
  feature "renders the rows a visitor reaches through the alternative naming nobody", %{
    session: session
  } do
    %{body: "shared_memo", shared: true}
    |> Memo.new()
    |> DB.create!()

    %{body: "shared_pinned_memo", pinned: true, shared: true}
    |> Memo.new()
    |> DB.create!()

    %{body: "private_memo"}
    |> Memo.new()
    |> DB.create!()

    session
    |> visit(Page2)
    |> assert_text(css("#memos"), ~r/^shared_memo,shared_pinned_memo$/)
    |> assert_text(css("#pinnable_memos"), ~r/^shared_memo$/)
  end

  # The session user reads their own memo through the alternative naming them, and may pin it
  # although it is pinned, while the authorless pinned memo stays out of reach. The reload renders
  # the page for the session user, and the memo then arrives on the stream, so both lists are
  # rendered in the browser - the memo list from the rows the server's read rule let through, the
  # pinnable list from the browser's own pin rule.
  feature "renders the rows the session user reaches through the alternative naming them", %{
    session: session
  } do
    %{body: "shared_memo", shared: true}
    |> Memo.new()
    |> DB.create!()

    %{body: "shared_pinned_memo", pinned: true, shared: true}
    |> Memo.new()
    |> DB.create!()

    session
    |> visit(Page2)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> reload()
    |> click(button("Write own memo"))
    |> assert_text(css("#result"), "wrote_own_memo")
    |> assert_text(css("#memos"), ~r/^own_memo,shared_memo,shared_pinned_memo$/)
    |> assert_text(css("#pinnable_memos"), ~r/^own_memo,shared_memo$/)
  end

  # The bookings whose guests fit their capacity - charlie exactly. The browser checks the rule
  # again over its own rows once they land, so the page the server sent is read as well: it
  # carries the answer the server's evaluator gave.
  feature "renders the rows a condition comparing two attributes grants", %{session: session} do
    seed_bookings()

    session
    |> visit(Page3)
    |> assert_text(css("#confirmable_bookings"), ~r/^alpha,charlie,delta$/)

    %HTTPoison.Response{body: html} = HTTPoison.get!("http://localhost:4002/policies/3")

    assert html =~ ~r{<strong id="confirmable_bookings"><code>alpha,charlie,delta</code></strong>}
  end

  # Bravo alone has more guests than places. The check runs in the browser, over local rows, and
  # answers the complement of the rendered list, which nothing rendered shows.
  feature "checks a condition comparing two attributes in the browser", %{session: session} do
    seed_bookings()

    session
    |> visit(Page3)
    |> await_local_fill()
    |> click(button("Check unconfirmable locally"))
    |> assert_text(css("#local_unconfirmable"), ~r/^bravo$/)
  end

  feature "adds a stop to a trip the session user may update", %{session: session} do
    trips = seed_trips()

    session
    |> visit(Page5)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")

    Auth.grant_role(session_user(), :editor, trips["own_trip"])

    session
    |> click(button("Add stop to own trip"))
    |> assert_text(css("#result"), "added_stop_to_own_trip")

    assert [%Stop{name: "own_trip_stop"}] = DB.read(Stop)
  end

  # The trip's create rule is open to everyone and is not asked - the stop asks the trip's update
  # rule, which wants an editor of a trip that is not archived.
  feature "refuses a stop on a trip the session user may not update", %{session: session} do
    trips = seed_trips()

    session
    |> visit(Page5)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")

    Auth.grant_role(session_user(), :editor, trips["archived_trip"])

    session
    |> click(button("Add stop to other trip"))
    |> assert_text(css("#result"), "refused_stop_on_other_trip")
    |> click(button("Add stop to archived trip"))
    |> assert_text(css("#result"), "refused_stop_on_archived_trip")

    assert DB.read(Stop) == []
  end

  # The grants arrive on the stream and the browser answers again over the rows it holds, asking
  # each trip's update rule, archived condition included. The archived trip's grant goes first, so
  # by the time the own trip shows, the browser has already answered for the archived one. The
  # reload renders the page for the session user: a login sets no context until a page renders.
  feature "checks the trip's update rule in the browser", %{session: session} do
    trips = seed_trips()

    session =
      session
      |> visit(Page5)
      |> click(button("Log in"))
      |> assert_text(css("#result"), "logged_in")
      |> reload()
      |> assert_text(css("#stoppable_trips"), ~r/^$/)
      |> mark_this_page_load()

    Auth.grant_role(session_user(), :editor, trips["archived_trip"])
    Auth.grant_role(session_user(), :editor, trips["own_trip"])

    session
    |> assert_text(css("#stoppable_trips"), ~r/^own_trip$/)
    |> assert_same_page_load()
  end

  feature "adds a leg through the trip's update rule two rows away", %{session: session} do
    trips = seed_legs()

    session
    |> visit(Page6)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")

    Auth.grant_role(session_user(), :editor, trips["archived_trip"])
    Auth.grant_role(session_user(), :editor, trips["own_trip"])

    session
    |> click(button("Add leg to own stop"))
    |> assert_text(css("#result"), "added_leg_to_own_stop")
    |> click(button("Add leg to archived stop"))
    |> assert_text(css("#result"), "refused_leg_on_archived_stop")

    names =
      Leg
      |> DB.read()
      |> Enum.map(& &1.name)
      |> Enum.sort()

    assert names == ["archived_leg", "other_leg", "own_leg", "own_stop_leg"]
  end

  feature "renames a leg through a role and a condition two rows away", %{session: session} do
    trips = seed_legs()

    session
    |> visit(Page6)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")

    Auth.grant_role(session_user(), :editor, trips["archived_trip"])
    Auth.grant_role(session_user(), :editor, trips["own_trip"])

    session
    |> click(button("Rename own leg"))
    |> assert_text(css("#result"), "renamed_own_leg")
    |> click(button("Rename other leg"))
    |> assert_text(css("#result"), "refused_rename_of_other_leg")
    |> click(button("Rename archived leg"))
    |> assert_text(css("#result"), "refused_rename_of_archived_leg")

    names =
      Leg
      |> DB.read()
      |> Enum.map(& &1.name)
      |> Enum.sort()

    assert names == ["archived_leg", "other_leg", "own_leg_renamed"]
  end

  # The grants arrive on the stream and the browser answers again over the rows it holds, following
  # each leg's stop to its trip: the create rule asks the trip's update rule, the rename rule a role
  # on the trip and the trip's archived flag. The archived trip's grant goes first, so by the time
  # the own trip's rows show, the browser has already answered for the archived one, and the other
  # trip's rows stay out for want of a role there. The reload renders the page for the session user:
  # a login sets no context until a page renders.
  feature "checks a path through two rows in the browser", %{session: session} do
    trips = seed_legs()

    session =
      session
      |> visit(Page6)
      |> click(button("Log in"))
      |> assert_text(css("#result"), "logged_in")
      |> reload()
      |> assert_text(css("#leggable_stops"), ~r/^$/)
      |> assert_text(css("#renamable_legs"), ~r/^$/)
      |> mark_this_page_load()

    Auth.grant_role(session_user(), :editor, trips["archived_trip"])
    Auth.grant_role(session_user(), :editor, trips["own_trip"])

    session
    |> assert_text(css("#leggable_stops"), ~r/^own_stop$/)
    |> assert_text(css("#renamable_legs"), ~r/^own_leg$/)
    |> assert_same_page_load()
  end

  # The page queries cabins and nothing else, and no page queries ships, so the ship the rename rule
  # reads reaches the browser only because the rule reads it - without it the browser answers no
  # for every cabin, whatever the role.
  feature "answers a check through rows no page queries", %{session: session} do
    ships = seed_ships()

    session
    |> visit(Page7)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")

    Auth.grant_role(session_user(), :captain, ships["own_ship"])

    session
    |> reload()
    |> mark_this_page_load()
    |> await_local_fill()
    |> assert_text(css("#renamable_cabins"), ~r/^own_cabin$/)
    |> assert_same_page_load()
  end

  # Archiving the ship changes no cabin, and the control still goes - the rows the rule reads are
  # kept current, so a change to one answers the check again on the same page load.
  feature "takes a control away when a row a rule reads changes", %{session: session} do
    ships = seed_ships()

    session
    |> visit(Page7)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")

    Auth.grant_role(session_user(), :captain, ships["own_ship"])

    session =
      session
      |> reload()
      |> await_local_fill()
      |> assert_text(css("#renamable_cabins"), ~r/^own_cabin$/)
      |> mark_this_page_load()

    DB.update!(Ship, ships["own_ship"].id, archived: true)

    session
    |> assert_text(css("#renamable_cabins"), ~r/^$/)
    |> assert_same_page_load()
  end
end
