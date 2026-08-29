defmodule HologramFeatureTests.Components.ActionWrites.Todos do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Todo

  # The todos reach this list through the ordinary read path - a registered query the client
  # evaluates against its own database - so a row an action wrote appears here in the same frame
  # as the action's state change, before anything has been sent. That is the whole claim the
  # scenarios check.
  prop :todos, [Todo], from_query: &todos_query/0

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
    order_by(Todo, :title)
  end
end
