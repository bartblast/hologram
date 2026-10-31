defmodule HologramFeatureTests.SyncPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Entities.Folder

  route "/sync"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    component
    |> put_state(:folder_name, "kept_folder")
    |> put_state(:local_folder, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="read_folder_locally">Read folder locally</button>
    </p>
    {%if @local_folder}
      <p>
        Local folder: <strong id="local_folder"><code>{@local_folder}</code></strong>
      </p>
    {/if}
    """
  end

  # The read runs in the browser over what its database holds. No page roots a folder, so one is
  # there only while a document the client may read includes it.
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
