defmodule HologramFeatureTests.Components.GrantQuery.GrantsOnDocument do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Auth.RoleGrant
  alias HologramFeatureTests.Entities.Document

  # The grant store queried the way an app queries it: by the entity the grants are held on,
  # named as its own module. The type is what keeps global grants - whose entity_type is nil -
  # out of a list about one document, and the label the browser compares here is the same string
  # the server stored, which is the whole point of naming the column after the entity.
  #
  # The prop the query binds is matched by NAME: grants_query/1's argument is document_id, so it
  # takes the value of the prop called that.
  #
  # No include(:user): the app's User is readable only by itself (allow :read, id: user_id()),
  # so a grant held by somebody else carries a nil user and there is no name to render. The row
  # names its holder by id, which is what the grant list on the optimistic page renders too.
  prop :document_id, :string
  prop :grants, [RoleGrant], from_query: &grants_query/1

  def template do
    ~HOLO"""
    <span id="grants">{%for grant <- @grants}{grant.role}:{grant.user_id},{/for}</span>
    """
  end

  defp grants_query(document_id) do
    RoleGrant
    |> filter(entity_id: document_id, entity_type: Document)
    |> order_by(:created_at)
  end
end
