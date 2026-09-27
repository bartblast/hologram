# Calls a repo's functions the way app code does, for the tests of what the data flow rules answer
# for them.
defmodule HologramEcosystemTests.Ecto.RepoCalls do
  alias HologramEcosystemTests.Ash.Item
  alias HologramEcosystemTests.Ecto.Post
  alias HologramEcosystemTests.Ecto.Repo

  def all, do: Repo.all(Post)

  def all_by, do: Repo.all_by(Post, title: "text")

  def fetched(id), do: Repo.get(Post, id)

  def fetched!(id), do: Repo.get!(Post, id)

  def fetched_resource(id), do: Repo.get(Item, id)

  def from_source, do: Repo.all("posts")

  def inserted, do: Repo.insert(%Post{title: "text"})

  def inserted!, do: Repo.insert!(%Post{title: "text"})

  def preloaded(id) do
    Post
    |> Repo.get!(id)
    |> Repo.preload(:comments)
  end

  def reloaded(post), do: Repo.reload(post)

  def unnamed(query), do: Repo.all(query)

  def updated(id) do
    Post
    |> Repo.get!(id)
    |> Ecto.Changeset.change(title: "text")
    |> Repo.update()
  end
end
