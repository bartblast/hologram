# The Ash fixtures the data flow rules are tested against: resources reached through the interfaces
# generated on them and on this domain.
defmodule HologramEcosystemTests.Ash.Domain do
  use Ash.Domain, otp_app: :hologram_ecosystem_tests

  alias HologramEcosystemTests.Ash.Category
  alias HologramEcosystemTests.Ash.Item
  alias HologramEcosystemTests.Ash.Note

  resources do
    resource Category

    resource Item do
      define :get_item, action: :read, get_by: [:id]
    end

    resource Note do
      namespace Notes

      define :list_notes, action: :read
      define :list_archived_notes, action: :read, namespace: Notes.Archive
    end
  end
end
