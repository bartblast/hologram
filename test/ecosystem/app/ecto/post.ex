# A schema with a field of each kind: plain, virtual, array, map, enum, of a type of the app's
# own, embedded and associated.
defmodule HologramEcosystemTests.Ecto.Post do
  use Ecto.Schema

  alias HologramEcosystemTests.Ecto.Comment
  alias HologramEcosystemTests.Ecto.Tag
  alias HologramEcosystemTests.Ecto.Types.Stamp
  alias HologramEcosystemTests.Ecto.Types.Version

  schema "posts" do
    field :draft, :string, virtual: true
    field :price, :decimal
    field :published_on, :date
    field :scores, {:array, :integer}
    field :settings, :map
    field :stamp, Stamp
    field :status, Ecto.Enum, values: [:draft, :published]
    field :title, :string
    field :version, Version
    field :visits, {:map, :date}

    embeds_one :main_tag, Tag
    embeds_many :tags, Tag

    has_many :comments, Comment
    has_many :comment_posts, through: [:comments, :post]

    timestamps(type: :utc_datetime)
  end
end
