defmodule HologramSyncTests.Components.ConsistencyLists do
  use Hologram.Component
  use Hologram.DB

  alias HologramSyncTests.Entities.Board
  alias HologramSyncTests.Entities.Card
  alias HologramSyncTests.Entities.Notice
  alias HologramSyncTests.Entities.NoticeBlock
  alias HologramSyncTests.Entities.Space
  alias HologramSyncTests.Entities.SpaceMember
  alias HologramSyncTests.Entities.Tag
  alias HologramSyncTests.Entities.User

  # A list per entity type, each giving the build a query over it, which is what makes sync send
  # the type: the simulated clients read the sync stream rather than the rendered page, and hold
  # every type the test checks. A card's tags and a tag's cards are included, so their rows travel
  # with the sets.
  derived :boards, [Board], fn -> sort(Board, name) end

  derived :cards, [Card], fn ->
    Card
    |> include(tags)
    |> sort(title)
  end

  derived :notice_blocks, [NoticeBlock], fn -> sort(NoticeBlock, id) end
  derived :notices, [Notice], fn -> sort(Notice, title) end
  derived :space_members, [SpaceMember], fn -> sort(SpaceMember, id) end
  derived :spaces, [Space], fn -> sort(Space, name) end

  derived :tags, [Tag], fn ->
    Tag
    |> include(cards)
    |> sort(name)
  end

  derived :users, [User], fn -> sort(User, name) end

  def template do
    ~HOLO"""
    <p>
      {length(@boards)} boards, {length(@cards)} cards, {length(@notices)} notices,
      {length(@notice_blocks)} notice blocks, {length(@spaces)} spaces,
      {length(@space_members)} space members, {length(@tags)} tags, {length(@users)} users
    </p>
    """
  end
end
