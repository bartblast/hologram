# credo:disable-for-this-file Credo.Check.Readability.Specs
# A row whose every verb rests on a rule of its own operation, for the contention tests. A create is
# granted by a type-wide :editor, or by :admin on the parent, a grant on another row that a batch
# can revoke. The :owner lines grant the delete a revoking batch crosses, and the batch's own
# revocation and update. The :publish line hands a :priority change to the parent, which the
# evaluation then reads FOR SHARE.
defmodule Hologram.Test.Fixtures.Policy.Module40 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module2

  attribute :priority, :integer, optional: true

  relationship :parent, Module2, optional: true

  role :editor
  role :owner

  allow :create, to: :editor
  allow :create, to: {:admin, parent}
  allow :update, to: :owner
  allow :update, as: :publish, only: [priority], via: {:publish, parent}
  allow :delete, to: :owner
  allow :revoke_role, to: :owner
end
