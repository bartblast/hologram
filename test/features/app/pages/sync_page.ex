defmodule HologramFeatureTests.SyncPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Folder

  route "/sync"

  layout HologramFeatureTests.Components.DefaultLayout

  state :document_title, :string
  state :folder_name, :string
  state :local_document_folder, :string
  state :local_folder, :string

  def init(_params, component, _server) do
    component
    |> put_state(:document_title, "points_at_the_folder")
    |> put_state(:folder_name, "kept_folder")
    |> put_state(:local_document_folder, nil)
    |> put_state(:local_folder, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="read_folder_locally">Read folder locally</button>
      <button $click="read_document_folder_locally">Read the document's folder locally</button>
    </p>
    {%if @local_folder}
      <p>
        Local folder: <strong id="local_folder"><code>{@local_folder}</code></strong>
      </p>
    {/if}
    {%if @local_document_folder}
      <p>
        Local document's folder:
        <strong id="local_document_folder"><code>{@local_document_folder}</code></strong>
      </p>
    {/if}
    """
  end

  # Whether the document, as the browser's database holds it, points at a folder - or isn't there.
  def action(:read_document_folder_locally, _params, component) do
    document_title = component.state.document_title

    document =
      Document
      |> filter(title == ^document_title)
      |> one()
      |> DB.read()

    local_document_folder =
      cond do
        document == nil -> "missing"
        document.folder_id == nil -> "none"
        true -> "linked"
      end

    put_state(component, :local_document_folder, local_document_folder)
  end

  # The read runs in the browser over what its database holds - every folder its user may read,
  # whether or not a document points at it.
  def action(:read_folder_locally, _params, component) do
    folder_name = component.state.folder_name

    names =
      Folder
      |> filter(name == ^folder_name)
      |> DB.read()
      |> Enum.map(& &1.name)

    put_state(component, :local_folder, local_folder_text(names))
  end

  defp local_folder_text([]), do: "none"

  defp local_folder_text(names), do: Enum.join(names, ",")
end
