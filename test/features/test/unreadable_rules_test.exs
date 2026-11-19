defmodule HologramFeatureTests.UnreadableRulesTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth
  alias Hologram.DB
  alias HologramFeatureTests.Entities.Parcel
  alias HologramFeatureTests.Entities.Shelf
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.Entities.Vault
  alias HologramFeatureTests.Policies.Page11

  # Each read rule of a parcel reads a vault or a shelf, types with no read line, so no browser ever
  # holds one. The server reads the stored rows, so it sends only the parcels the rules admit. The
  # browser can't read the vault or the shelf, so it answers can? from the server's verdict on each
  # parcel it was sent: through a condition on the vault, a role held on the vault the shelf names,
  # or the vault's own update rule.
  #
  # Other tables reference the user table, so every table truncates with it.
  setup do
    await_evaluator_drain()

    truncate_every_entity_table()
  end

  defp assert_arrives_readable(session, label) do
    session
    |> assert_text(css("#parcels"), label)
    |> assert_text(css("#readable_parcels"), label)
    |> assert_same_page_load()
  end

  # A second visit waits for the mount, so the assertion reads what the browser answered, not the
  # server's render.
  defp assert_readable_on_visit(session, labels) do
    session
    |> visit(Page11)
    |> assert_text(css("#parcels"), labels)
    |> assert_text(css("#readable_parcels"), labels)
  end

  defp await_empty(session) do
    session
    |> reload()
    |> await_local_fill()
    |> assert_text(css("#parcels"), ~r/^$/)
    |> mark_this_page_load()
  end

  defp create(entity_type, values) do
    values
    |> entity_type.new()
    |> DB.create!()
  end

  defp grant_keeper(vault) do
    user =
      User
      |> DB.read()
      |> Enum.find(&(&1.email == "keeper@example.com"))

    Auth.grant_role(user, :keeper, vault)
  end

  defp log_in(session) do
    session
    |> visit(Page11)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
  end

  feature "lets the user read a parcel in an open vault held when the page loads", %{
    session: session
  } do
    create(Parcel, %{label: "alpha", vault_id: create(Vault, %{open: true}).id})
    create(Parcel, %{label: "beta", vault_id: create(Vault, %{open: false}).id})

    session
    |> log_in()
    |> assert_readable_on_visit(~r/^alpha$/)
  end

  feature "lets the user read a parcel on a shelf of their vault held when the page loads", %{
    session: session
  } do
    vault = create(Vault, %{open: false})
    create(Parcel, %{label: "gamma", shelf_id: create(Shelf, %{vault_id: vault.id}).id})
    other_vault = create(Vault, %{open: false})
    create(Parcel, %{label: "delta", shelf_id: create(Shelf, %{vault_id: other_vault.id}).id})

    session = log_in(session)
    grant_keeper(vault)

    assert_readable_on_visit(session, ~r/^gamma$/)
  end

  feature "lets the user read a parcel in a vault they may update held when the page loads", %{
    session: session
  } do
    vault = create(Vault, %{open: false})
    create(Parcel, %{label: "epsilon", vault_id: vault.id})
    create(Parcel, %{label: "zeta", vault_id: create(Vault, %{open: false}).id})

    session = log_in(session)
    grant_keeper(vault)

    assert_readable_on_visit(session, ~r/^epsilon$/)
  end

  feature "lets the user read a parcel in an open vault arriving on the stream", %{
    session: session
  } do
    vault = create(Vault, %{open: false})
    create(Parcel, %{label: "eta", vault_id: vault.id})

    session =
      session
      |> log_in()
      |> await_empty()

    DB.update!(Vault, vault.id, open: true)

    assert_arrives_readable(session, ~r/^eta$/)
  end

  feature "lets the user read a parcel on a shelf of their vault arriving on the stream", %{
    session: session
  } do
    vault = create(Vault, %{open: false})
    create(Parcel, %{label: "theta", shelf_id: create(Shelf, %{vault_id: vault.id}).id})

    session =
      session
      |> log_in()
      |> await_empty()

    grant_keeper(vault)

    assert_arrives_readable(session, ~r/^theta$/)
  end

  feature "lets the user read a parcel in a vault they may update arriving on the stream", %{
    session: session
  } do
    vault = create(Vault, %{open: false})
    create(Parcel, %{label: "iota", vault_id: vault.id})

    session =
      session
      |> log_in()
      |> await_empty()

    grant_keeper(vault)

    assert_arrives_readable(session, ~r/^iota$/)
  end
end
