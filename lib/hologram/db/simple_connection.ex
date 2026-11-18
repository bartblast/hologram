defmodule Hologram.DB.SimpleConnection do
  @moduledoc false

  # TODO(#1696): delete this module once a Postgrex release returns a connection error from a socket
  # call that fails as a connection opens, and require that release. Its callers then start
  # Postgrex.SimpleConnection.start_link/3 again.
  #
  # Postgrex.SimpleConnection, started so that a connect whose socket fails as it opens fails like
  # any other connect instead of raising - see Hologram.DB.Protocol for the raise.
  # Postgrex.SimpleConnection runs the connect itself and handles only a returned error, so a raise
  # ends the process: a connection set to keep trying doesn't, its supervisor counts a restart, and
  # a start that connects at once fails with the raw match error.
  #
  # The process runs Postgrex.SimpleConnection's own gen_statem callbacks, through this module,
  # which catches the raise around each connect. Calls, replies and the callback modules don't
  # change, since Postgrex.SimpleConnection.call/3 and reply/2 only go through :gen_statem.
  #
  # It leans on what Postgrex.SimpleConnection doesn't document: its gen_statem callbacks, public
  # but @doc false, the internal {:connect, _} event it connects on, the :auto_reconnect,
  # :reconnect_backoff and :state fields of its state, what it does after a connect that returned
  # an error (the log line, then the {:timeout, :backoff} action or a stop), what its init/1
  # returns for a start that connects later, the three results of a connect, which init/1 below
  # maps, and that nothing reads the :sync_connect option after init/1, which this module turns
  # off there. The tests catch a Postgrex release that changes them.
  #
  # An init/1 result this module doesn't recognise costs the catch on the first connect. For a
  # start that connects later it's passed on as it is. A start asked to connect at once throws it
  # away and calls Postgrex.SimpleConnection.init/1 again, to connect without the catch - so the
  # callback module's init/1 runs twice, which is safe only while it does nothing but build its
  # state, as the three callers' do, and while the first, thrown-away call started nothing. A
  # connect result it doesn't recognise fails the start.

  @behaviour :gen_statem

  require Logger

  alias Hologram.DB.Protocol
  alias Postgrex.SimpleConnection

  @doc """
  Starts a connection with the given callback module, its init argument and the given options,
  linked to the caller - the same as Postgrex.SimpleConnection.start_link/3, whose options it
  takes.
  """
  @spec start_link(module, term, keyword) :: {:ok, pid} | {:error, term}
  def start_link(module, args, opts) do
    {name, given_opts} = Keyword.pop(opts, :name)

    # TODO(#1696): Postgrex.SimpleConnection.start_link/3 fills in the defaults the same way,
    # through Postgrex.Utils.default_opts/1, which is public but undocumented.
    connection_opts =
      given_opts
      |> Keyword.put_new(:sync_connect, true)
      |> Postgrex.Utils.default_opts()

    start_args = {module, args, connection_opts}

    case name do
      nil ->
        :gen_statem.start_link(__MODULE__, start_args, [])

      atom when is_atom(atom) ->
        :gen_statem.start_link({:local, atom}, __MODULE__, start_args, [])

      {:global, _term} = tuple ->
        :gen_statem.start_link(tuple, __MODULE__, start_args, [])

      {:via, via_module, _term} = tuple when is_atom(via_module) ->
        :gen_statem.start_link(tuple, __MODULE__, start_args, [])

      other ->
        raise ArgumentError,
              "expected :name to be nil, an atom, {:global, term} or {:via, module, term}, got: #{inspect(other)}"
    end
  end

  @impl :gen_statem
  defdelegate callback_mode, to: SimpleConnection

  @impl :gen_statem
  defdelegate format_status(opts, status), to: SimpleConnection

  @impl :gen_statem
  def handle_event(:internal, {:connect, _info} = event, state_name, state) do
    case Protocol.rescue_peer_reset(fn ->
           SimpleConnection.handle_event(:internal, event, state_name, state)
         end) do
      {:error, %DBConnection.ConnectionError{} = error} -> fail_connect(error, state)
      result -> result
    end
  end

  def handle_event(type, content, state_name, state) do
    SimpleConnection.handle_event(type, content, state_name, state)
  end

  # Postgrex.SimpleConnection connects inside its own init/1 when the connect is synchronous, past
  # handle_event/4 above, so it's asked for an asynchronous start, whose connect this module then
  # runs right away, mapping the result the way Postgrex.SimpleConnection.init/1 does.
  @impl :gen_statem
  def init({module, args, opts}) do
    sync_connect? = opts[:sync_connect] not in [nil, false]
    async_start = SimpleConnection.init({module, args, Keyword.put(opts, :sync_connect, false)})

    case async_start do
      {:ok, state_name, state, {:next_event, :internal, {:connect, :init} = event}}
      when sync_connect? ->
        result = handle_event(:internal, event, state_name, state)

        init_result(result, state_name)

      # A result this module doesn't recognise, from a start asked to connect at once: the connect
      # is left to Postgrex.SimpleConnection.init/1, without the catch.
      _other when sync_connect? ->
        SimpleConnection.init({module, args, opts})

      _other ->
        async_start
    end
  end

  # What Postgrex.SimpleConnection logs for a connect that returned an error, and what it does next.
  defp fail_connect(error, %{state: {module, _module_state}} = state) do
    Logger.error(
      "#{inspect(name_or_pid())} (#{inspect(module)}) failed to connect to Postgres: #{Exception.format(:error, error)}"
    )

    if state.auto_reconnect do
      {:keep_state, state, {{:timeout, :backoff}, state.reconnect_backoff, nil}}
    else
      {:stop, error, state}
    end
  end

  defp init_result({:keep_state, state}, state_name), do: {:ok, state_name, state}

  defp init_result({:keep_state, state, actions}, state_name),
    do: {:ok, state_name, state, actions}

  defp init_result({:stop, reason, _state}, _state_name), do: {:stop, reason}

  defp name_or_pid do
    case Process.info(self(), :registered_name) do
      {:registered_name, name} when is_atom(name) -> name
      _no_name -> self()
    end
  end
end
