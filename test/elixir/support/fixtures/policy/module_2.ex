# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module2 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Role.Module1, as: Role1

  attribute :public, :boolean, default: false

  role :admin
  role :member

  allow :read, to: :member
  allow :archive, to: Role1
  allow :publish, public: true
  allow :update, to: :admin
  allow :grant_role, to: [:admin, :member, Role1]
  allow :read_roles, to: :member
  allow :revoke_role, to: [:admin, :member, Role1]
end
