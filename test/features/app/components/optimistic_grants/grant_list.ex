defmodule HologramFeatureTests.Components.OptimisticGrants.GrantList do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Auth.RoleGrant

  # The grant store's rows as this client holds them - the window a permission-checking page
  # downloads, read through the overlay, so a grant an action just made (or just revoked) shows
  # here before anything is sent.
  prop :grants, [RoleGrant], from_query: fn -> RoleGrant end

  def template do
    ~HOLO"""
    <span id="grants">{%for grant <- @grants}{grant.role}:{grant.user_id},{/for}</span>
    """
  end
end
