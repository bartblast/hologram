defmodule HologramClusterTests.Entities.User do
  # Designated, and this app declares NO role - on purpose. The designation is what puts the
  # role grant store in the model, and the store's role enum takes its values from the app's
  # roles, so with none declared the model derives a type with no values and a production
  # node has to boot on one. That is the case migration_test.exs's "a production node boots
  # on a history that designates a user entity before any role" exists for, and its
  # assertion that the type is valueless is what keeps this comment true: declare a role
  # anywhere in this app and that test fails, so move the case before you do.
  use Hologram.Entity, user: true

  attribute :email, :string

  # No relationship to Item in either direction: a reference would pull both tables into
  # sync_test.exs's truncate, which names one table today.
  allow :read, id: user_id()
end
