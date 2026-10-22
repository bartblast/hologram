defmodule HologramFeatureTests.Components.Policies.Component5 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.Roles.Admin

  prop :current_user, User, from_context: {Hologram, :user}
  prop :documents, [Document], from_query: &documents_query/0

  # Checked while RENDERING, so the checks ship to the client and answer again on every render the
  # stream or an action schedules. No init/3: both props are rendered as they resolve.
  def template do
    ~HOLO"""
    <p>
      Documents: <strong id="documents"><code>{Enum.map_join(@documents, ",", & &1.title)}</code></strong>
    </p>
    <p>
      Admin: <strong id="admin"><code>{has_role?(@current_user, Admin)}</code></strong>
    </p>
    <p>
      Editor on: <strong id="editor_documents"><code>{titles_held(@current_user, :editor, @documents)}</code></strong>
    </p>
    <p>
      Owner on: <strong id="owner_documents"><code>{titles_held(@current_user, :owner, @documents)}</code></strong>
    </p>
    """
  end

  defp documents_query do
    order_by(Document, title)
  end

  defp titles_held(user, role, documents) do
    documents
    |> Enum.filter(&has_role?(user, role, &1))
    |> Enum.map_join(",", & &1.title)
  end
end
