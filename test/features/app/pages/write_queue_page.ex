defmodule HologramFeatureTests.WriteQueuePage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.ActionWrites.Todos
  alias HologramFeatureTests.Entities.Todo
  alias HologramFeatureTests.Entities.User

  route "/write-queue"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  # Every action here writes in the BROWSER, and what the scenarios do is keep the write from
  # reaching the server - hold it, reload the page, sign somebody else in - and then ask what the
  # browser does with it. The Todo entity's allow lines are bare, so the sign-in commands are not
  # there for policy: they are there to change who the page is mounted under, which is what decides
  # whose stored batches a page takes up.
  #
  # A button is clicked by a label the browser driver matches as a SUBSTRING, so no label here may
  # contain another's - "Create alpha" and "Create a duplicate slug" share a prefix but neither is
  # inside the other.
  def template do
    ~HOLO"""
    <p>
      <button $click={action: :create_alpha}> Create alpha </button>
      <button $click={action: :create_duplicate_slug}> Create a duplicate slug </button>
      <button $click={action: :create_gamma}> Create gamma </button>
      <button $click={command: :log_in_as_alice}> Log in as Alice </button>
      <button $click={command: :log_in_as_bob}> Log in as Bob </button>
      <button $click={action: :rename_alpha}> Rename alpha </button>
    </p>
    <Todos cid="todos" />
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:create_alpha, _params, component) do
    {:ok, todo} =
      %{title: "alpha"}
      |> Todo.new()
      |> DB.create()

    put_state(component, :result, "created_#{todo.title}")
  end

  # Uniqueness is a question about rows this client does not hold, so the create passes here and
  # the server refuses the batch afterwards - which is what makes it the write to hold back and
  # replay from a store: the refusal lands on a page that did not make it.
  def action(:create_duplicate_slug, _params, component) do
    {:ok, _todo} =
      %{slug: "taken", title: "dup"}
      |> Todo.new()
      |> DB.create()

    put_state(component, :result, "created_dup")
  end

  # A second create, so that two TABS can each make one and the numbers they are filed under can be
  # told apart. Nothing about it differs from creating alpha but the title.
  def action(:create_gamma, _params, component) do
    {:ok, todo} =
      %{title: "gamma"}
      |> Todo.new()
      |> DB.create()

    put_state(component, :result, "created_#{todo.title}")
  end

  # Reads alpha from the client's own database - through the overlay, so a pending create of it
  # is enough - and writes a batch that names the row the earlier batch created.
  def action(:rename_alpha, _params, component) do
    Todo
    |> filter(title: "alpha")
    |> one()
    |> DB.read()
    |> put_attribute(title: "beta")
    |> DB.update!()

    put_state(component, :result, "renamed_beta")
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:log_in_as_alice, _params, server) do
    log_in_as(server, "alice@example.com", "logged_in_alice")
  end

  def command(:log_in_as_bob, _params, server) do
    log_in_as(server, "bob@example.com", "logged_in_bob")
  end

  # Finds the user rather than creating another one with the same email: a returning owner has to
  # come back as the SAME user id, or the store never sees them return and their batches wait
  # forever. Trusted on both sides, since a User allows only its own row to be read.
  defp log_in_as(server, email, result) do
    user = find_user(email) || create_user(email)

    put_action(%{server | user_id: user.id}, :show_result, result: result)
  end

  defp create_user(email) do
    %{email: email}
    |> User.new()
    |> trust()
    |> DB.create!()
  end

  defp find_user(email) do
    User
    |> filter(email: email)
    |> one()
    |> trust()
    |> DB.read()
  end
end
