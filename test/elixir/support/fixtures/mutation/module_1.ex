# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mutation.Module1 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module14

  attribute :priority, :integer, optional: true
  attribute :public, :boolean, default: false

  relationship :author, Module14, optional: true

  role :maintainer, granted_to: :creator

  allow :read, when: public == true
  allow :create, when: author_id == user_id()
  allow :update, when: author_id == user_id()
  allow :delete, when: author_id == user_id()
end
