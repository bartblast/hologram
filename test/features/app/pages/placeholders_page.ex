defmodule HologramFeatureTests.PlaceholdersPage do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Entity.NotIncluded
  alias Hologram.Entity.ServerOnly
  alias HologramFeatureTests.Entities.Document

  route "/placeholders"

  layout HologramFeatureTests.Components.DefaultLayout

  # The same documents read twice, once without the folder and once with it, so each field holds
  # a placeholder in one read and a value in the other.
  derived :documents, [Document], fn -> sort(Document, title) end

  derived :documents_with_folder, [Document], fn ->
    Document
    |> include(folder)
    |> sort(title)
  end

  state :result, :string

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={action: :match_placeholders}> Match placeholders </button>
    </p>
    <p>
      Folder without include: <strong id="folder_without_include"><code>{%for document <- @documents}{%if match?(%NotIncluded{}, document.folder)}not_included{%else}value{/if}{/for}</code></strong>
    </p>
    <p>
      Folder with include: <strong id="folder_with_include"><code>{%for document <- @documents_with_folder}{%if match?(%NotIncluded{}, document.folder)}not_included{%else}value{/if}{/for}</code></strong>
    </p>
    <p>
      API token: <strong id="api_token"><code>{%for document <- @documents}{%if match?(%ServerOnly{}, document.api_token)}server_only{%else}value{/if}{/for}</code></strong>
    </p>
    <p>
      Title: <strong id="title"><code>{%for document <- @documents}{%if match?(%ServerOnly{}, document.title)}server_only{%else}value{/if}{/for}</code></strong>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:match_placeholders, _params, component) do
    [document] = component.derived.documents
    [document_with_folder] = component.derived.documents_with_folder

    result =
      Enum.map_join(
        [
          folder_kind(document.folder),
          folder_kind(document_with_folder.folder),
          attribute_kind(document.api_token),
          attribute_kind(document.title)
        ],
        ",",
        &Atom.to_string/1
      )

    put_state(component, :result, result)
  end

  defp folder_kind(%NotIncluded{}), do: :not_included

  defp folder_kind(_folder), do: :value

  defp attribute_kind(%ServerOnly{}), do: :server_only

  defp attribute_kind(_value), do: :value
end
