defmodule HologramFeatureTests.ServerOnlyTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Folder
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.PoliciesPage

  # All four tables truncate in one statement: the role grant table's foreign keys to the
  # user table make Postgres reject truncating the referenced table alone.
  setup do
    tables =
      Enum.map_join([Document, Folder, Note, RoleGrant, User], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  # The payload is fetched over HTTP rather than read with page_source/1: the browser reports
  # the hydrated DOM, which no longer carries the component registry the row travels in.
  feature "delivers the row while keeping its server-only value out of the page", %{
    session: session
  } do
    %{api_token: "api_token_5rL9", public: true, title: "public_document"}
    |> Document.new()
    |> DB.create!()

    session
    |> visit(PoliciesPage)
    |> assert_text(css("#documents"), "public_document")

    %HTTPoison.Response{body: html} = HTTPoison.get!("http://localhost:4002/policies")

    assert String.contains?(html, "componentRegistry")
    assert String.contains?(html, "public_document")

    refute String.contains?(html, "api_token_5rL9")
  end
end
