defmodule HologramFeatureTests.Components.FieldRules.BulletinPanel do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Bulletin
  alias HologramFeatureTests.Entities.User

  prop :current_user, User, from_context: {Hologram, :user}

  derived :bulletins, [Bulletin], &bulletins_query/0

  # The rename control is shown by can? while RENDERING, so the check ships to the client and
  # answers there as well.
  def template do
    ~HOLO"""
    {%for bulletin <- @bulletins}
      <p>
        Title: <strong id="title"><code>{bulletin.title}</code></strong>
      </p>
      <p>
        Topic: <strong id="topic"><code>{bulletin.topic}</code></strong>
      </p>
      {%if renamable?(@current_user, bulletin)}
        <p>
          <button $click={action: :change_title, target: "page"}> Rename bulletin </button>
        </p>
      {/if}
    {/for}
    """
  end

  defp bulletins_query do
    sort(Bulletin, title)
  end

  defp renamable?(user, bulletin) do
    can?(user, :rename, bulletin)
  end
end
