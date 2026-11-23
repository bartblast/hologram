defmodule HologramFeatureTests.ActionWritesPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.ActionWrites.Todos
  alias HologramFeatureTests.Entities.Todo
  alias HologramFeatureTests.Entities.User

  route "/action-writes"

  layout HologramFeatureTests.Components.DefaultLayout

  state :result, :string

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  # Every one of these runs in the BROWSER, against the client's own database. What makes them
  # worth running at all is that the same four verbs reach Postgres when a command calls them -
  # here they reach a memory graph, and the row is on screen before anything has been sent.
  #
  # A button is clicked by a label the browser driver matches as a SUBSTRING, so no label here may
  # contain another's - which is why the two that add one todo and one with a taken slug are
  # worded apart rather than sharing a prefix.
  def template do
    ~HOLO"""
    <p>
      <button $click={command: :log_in}> Log in </button>
      <button $click={action: :add_todo_holding_nul}> Add a todo holding a NUL </button>
      <button $click={action: :add_todo_to_corrupt}> Add a todo the test corrupts </button>
      <button $click={action: :add_todo_with_taken_slug}> Add a todo with a taken slug </button>
      <button $click={action: :add_one_todo}> Add one todo </button>
      <button $click={action: :add_two_todos}> Add two todos </button>
      <button $click={action: :delete_todo}> Delete the todo </button>
      <button $click={action: :raise_after_adding}> Raise after adding </button>
      <button $click={action: :read_own_write}> Read own write </button>
      <button $click={action: :refuse_empty_title}> Refuse an empty title </button>
      <button $click={action: :rename_todo}> Rename the todo </button>
      <button $click={action: :retract_vote}> Retract a vote </button>
      <button $click={action: :vote}> Vote </button>
    </p>
    <Todos cid="todos" />
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:add_one_todo, _params, component) do
    {:ok, todo} =
      %{title: "alpha"}
      |> Todo.new()
      |> DB.create()

    put_state(component, :result, "created_#{todo.title}")
  end

  # A NUL is valid text that no PostgreSQL text column can hold, so the browser refuses it here
  # rather than queue a write the database would never take.
  def action(:add_todo_holding_nul, _params, component) do
    {:error, %{title: [{:type, :string}]}} =
      %{title: "a\0b"}
      |> Todo.new()
      |> DB.create()

    put_state(component, :result, "refused_nul")
  end

  # Valid as written. A test rewrites this title in the browser's stored queue to one holding a NUL,
  # which stands in for a batch queued before the browser's validator refused such a value.
  def action(:add_todo_to_corrupt, _params, component) do
    {:ok, _todo} =
      %{title: "corrupt-me"}
      |> Todo.new()
      |> DB.create()

    put_state(component, :result, "created_to_corrupt")
  end

  # Uniqueness is a question about rows this client does not hold, so the create passes here and
  # the server refuses the batch afterwards.
  def action(:add_todo_with_taken_slug, _params, component) do
    {:ok, _todo} =
      %{slug: "taken", title: "dup"}
      |> Todo.new()
      |> DB.create()

    put_state(component, :result, "created_dup")
  end

  def action(:add_two_todos, _params, component) do
    {:ok, _first} =
      %{title: "alpha"}
      |> Todo.new()
      |> DB.create()

    {:ok, _second} =
      %{title: "beta"}
      |> Todo.new()
      |> DB.create()

    put_state(component, :result, "created_two")
  end

  def action(:delete_todo, _params, component) do
    Todo
    |> filter(title: "alpha")
    |> one()
    |> DB.read()
    |> DB.delete()

    put_state(component, :result, "deleted")
  end

  # Nothing half-done: the action's writes go away with it, so the row this made never appears and
  # no batch is ever sent.
  def action(:raise_after_adding, _params, _component) do
    {:ok, _todo} =
      %{title: "never"}
      |> Todo.new()
      |> DB.create()

    raise "boom"
  end

  def action(:read_own_write, _params, component) do
    {:ok, _todo} =
      %{title: "alpha"}
      |> Todo.new()
      |> DB.create()

    todo =
      Todo
      |> filter(title: "alpha")
      |> one()
      |> DB.read()

    put_state(component, :result, "read_#{todo.title}")
  end

  # The declarations are baked into the bundle, so this refusal never leaves the browser.
  def action(:refuse_empty_title, _params, component) do
    {:error, %{title: [{:min_length, min_length}]}} =
      %{title: ""}
      |> Todo.new()
      |> DB.create()

    put_state(component, :result, "refused_min_length_#{min_length}")
  end

  def action(:rename_todo, _params, component) do
    Todo
    |> filter(title: "alpha")
    |> one()
    |> DB.read()
    |> put_attribute(title: "beta")
    |> DB.update!()

    put_state(component, :result, "renamed_beta")
  end

  def action(:retract_vote, _params, component) do
    Todo
    |> filter(title: "alpha")
    |> one()
    |> DB.read()
    |> decrement(:votes, 1)
    |> DB.update!()

    put_state(component, :result, "retracted_1")
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def action(:vote, _params, component) do
    Todo
    |> filter(title: "alpha")
    |> one()
    |> DB.read()
    |> increment(:votes, 1)
    |> DB.update!()

    put_state(component, :result, "voted_1")
  end

  def command(:log_in, _params, server) do
    user =
      %{email: "action-writes@example.com"}
      |> User.new()
      |> trust()
      |> DB.create!()

    put_action(%{server | user_id: user.id}, :show_result, result: "logged_in")
  end
end
