defmodule HologramFeatureTests.Components.SyncedTypes.TodoCount do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Todo

  # A count reaches the browser as the number the server rendered, which it shows until it holds
  # every todo it may see - and then counts its own rows, a write it just made included.
  derived :todo_count, :integer, fn -> count(Todo) end

  def template do
    ~HOLO"""
    <p>
      Todos: <strong id="todo_count"><code>{@todo_count}</code></strong>
    </p>
    """
  end
end
