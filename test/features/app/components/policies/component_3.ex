defmodule HologramFeatureTests.Components.Policies.Component3 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.User

  prop :current_user, User, from_context: {Hologram, :user}
  prop :memos, [Memo], from_query: &memos_query/0

  # Checked while RENDERING, so the check ships to the client and answers there as well. No
  # init/3: both props are rendered as they resolve.
  def template do
    ~HOLO"""
    <p>
      Memos: <strong id="memos"><code>{Enum.map_join(@memos, ",", & &1.body)}</code></strong>
    </p>
    <p>
      Pinnable: <strong id="pinnable_memos"><code>{Enum.map_join(pinnable(@current_user, @memos), ",", & &1.body)}</code></strong>
    </p>
    """
  end

  defp memos_query do
    order_by(Memo, body)
  end

  defp pinnable(user, memos) do
    Enum.filter(memos, &can?(user, :pin, &1))
  end
end
