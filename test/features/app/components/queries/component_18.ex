defmodule HologramFeatureTests.Components.Queries.Component18 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Membership
  alias HologramFeatureTests.Entities.Post

  derived :unread_count, :integer, &unread_count_query/0
  derived :visible_posts, [Post], &visible_posts_query/0

  def template do
    ~HOLO"""
    <p>
      Unread channels: <strong id="unread_count"><code>{@unread_count}</code></strong>
    </p>
    <p>
      Visible posts: <strong id="visible_posts"><code>{bodies(@visible_posts)}</code></strong>
    </p>
    """
  end

  defp bodies([]), do: "(none)"

  defp bodies(posts), do: Enum.map_join(posts, ",", & &1.body)

  # The memberships whose channel holds a message past the one the member last saw - the unread
  # dot, compared against the membership's own position from inside the channel's messages.
  defp unread_count_query do
    Membership
    |> filter(any(message <- channel.messages, message.position > seen_position))
    |> count()
  end

  # The posts that stand, and the deleted ones a standing reply still hangs off - the replies are
  # posts too.
  defp visible_posts_query do
    Post
    |> filter(deleted == false or any(reply <- replies, reply.deleted == false))
    |> sort(body)
  end
end
