defmodule HologramFeatureTests.Policies.Editable do
  use Hologram.Policy

  alias HologramFeatureTests.Roles.Admin

  role :editor
  role :owner, extends: :editor

  allow :read, to: [:editor, :owner]
  allow :grant_role, to: [:editor, :owner, Admin]
  allow :revoke_role, to: [:editor, :owner, Admin]
end
