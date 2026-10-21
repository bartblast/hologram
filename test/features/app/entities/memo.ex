defmodule HologramFeatureTests.Entities.Memo do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.User

  attribute :body, :string
  attribute :pinned, :boolean, default: false
  attribute :shared, :boolean, default: false

  relationship :author, User, optional: true

  allow :read, when: author_id == user_id() or shared == true
  allow :pin, when: pinned == false or author_id == user_id()
end
