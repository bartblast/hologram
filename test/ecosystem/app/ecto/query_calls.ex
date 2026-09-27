# Builds queries and changesets the way app code does, and hands them to a repo, for the tests of
# what the data flow rules answer for them.
defmodule HologramEcosystemTests.Ecto.QueryCalls do
  import Ecto.Query

  alias Ecto.Changeset
  alias HologramEcosystemTests.Ecto.Comment
  alias HologramEcosystemTests.Ecto.Post
  alias HologramEcosystemTests.Ecto.Repo

  def applied(params) do
    %Post{}
    |> Changeset.cast(params, [:title])
    |> Changeset.apply_action!(:insert)
  end

  def built(params) do
    %Post{}
    |> Changeset.cast(params, [:stamp, :title])
    |> Changeset.validate_required([:title])
  end

  def by_literal, do: Repo.all(from(p in Post, where: p.title == "text"))

  def by_pipeline do
    Post
    |> where([p], p.title == "text")
    |> order_by([p], p.title)
    |> Repo.all()
  end

  def by_subquery, do: Repo.all(subquery(from(p in Post)))

  def inserted(params), do: params |> built() |> Repo.insert()

  def joined do
    Repo.all(from(p in Post, join: c in Comment, on: c.post_id == p.id, select: {p, c}))
  end

  def schemaless(params) do
    {%{}, %{name: :string}}
    |> Changeset.cast(params, [:name])
    |> Changeset.validate_required([:name])
  end
end
