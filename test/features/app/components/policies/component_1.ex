defmodule HologramFeatureTests.Components.Policies.Component1 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.User

  prop :current_user, User, from_context: {Hologram, :user}
  prop :documents, [Document], from_query: &documents_query/0

  # The query result arrives as a server-injected prop and hydrates the client
  # through state - client-side from_query rendering runs on the local database,
  # which is not built yet.
  def init(props, component, _server) do
    component
    |> put_state(:current_user, props.current_user)
    |> put_state(:documents, props.documents)
  end

  def template do
    ~HOLO"""
    <p>
      Documents: <strong id="documents"><code>{Enum.map_join(@documents, ",", & &1.title)}</code></strong>
    </p>
    <p>
      Folders: <strong id="folders"><code>{Enum.map_join(@documents, ",", &folder_name(&1.folder))}</code></strong>
    </p>
    <p>
      Session user: <strong id="session_user"><code>{session_user_email(@current_user)}</code></strong>
    </p>
    """
  end

  defp documents_query do
    Document
    |> include(:folder)
    |> order_by(:title)
  end

  defp folder_name(nil), do: "none"

  defp folder_name(folder), do: folder.name

  defp session_user_email(nil), do: "anonymous"

  defp session_user_email(user), do: user.email
end
