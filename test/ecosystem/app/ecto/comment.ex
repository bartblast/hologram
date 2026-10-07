defmodule HologramEcosystemTests.Ecto.Comment do
  use Ecto.Schema

  alias HologramEcosystemTests.Ecto.Post

  schema "comments" do
    field :text, :string

    belongs_to :post, Post
  end
end
