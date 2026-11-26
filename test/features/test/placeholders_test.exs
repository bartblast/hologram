defmodule HologramFeatureTests.PlaceholdersTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Folder
  alias HologramFeatureTests.PlaceholdersPage

  setup do
    truncate_entity_tables([Document, Folder, RoleGrant])

    folder =
      %{name: "folder_alpha", public: true}
      |> Folder.new()
      |> DB.create!()

    %{api_token: "api_token_7kQ2", folder_id: folder.id, public: true, title: "document_alpha"}
    |> Document.new()
    |> DB.create!()

    :ok
  end

  feature "a template tells a not-included relationship from a value", %{session: session} do
    session
    |> visit(PlaceholdersPage)
    |> await_local_fill()
    |> assert_text(css("#folder_without_include"), ~r/^not_included$/)
    |> assert_text(css("#folder_with_include"), ~r/^value$/)
  end

  feature "a template tells a server-only attribute from a value", %{session: session} do
    session
    |> visit(PlaceholdersPage)
    |> await_local_fill()
    |> assert_text(css("#api_token"), ~r/^server_only$/)
    |> assert_text(css("#title"), ~r/^value$/)
  end

  feature "an action and a template in the browser tell a placeholder from a value", %{
    session: session
  } do
    session
    |> visit(PlaceholdersPage)
    |> await_local_fill()
    |> click(button("Match placeholders"))
    |> assert_text(css("#result"), ~r/^not_included,value,server_only,value$/)
    |> assert_text(css("#folder_without_include"), ~r/^not_included$/)
    |> assert_text(css("#folder_with_include"), ~r/^value$/)
    |> assert_text(css("#api_token"), ~r/^server_only$/)
    |> assert_text(css("#title"), ~r/^value$/)
  end
end
