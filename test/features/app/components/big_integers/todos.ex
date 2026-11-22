defmodule HologramFeatureTests.Components.BigIntegers.Todos do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Todo

  # Sorted by the big integer itself, so the order on screen is the browser's own comparison of
  # two values a JavaScript number can't tell apart.
  derived :todos, [Todo], &todos_query/0

  def template do
    ~HOLO"""
    <ul id="todos">
      {%for todo <- @todos}
        <li>{todo.title} {todo.votes}</li>
      {/for}
    </ul>
    """
  end

  defp todos_query do
    sort(Todo, votes: :desc)
  end
end
