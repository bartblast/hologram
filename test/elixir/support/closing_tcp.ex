defmodule Hologram.Test.ClosingTCP do
  @moduledoc false

  # A gen_tcp callback module, passed as the :tcp_module socket option, whose connections close as
  # they open: connect/4 connects, then closes the socket before handing it over. Postgrex's next
  # call on the socket returns {:error, :einval}, the way a call on a socket the peer reset right
  # after accepting does (#1667). A real reset can't be timed to land between the connect and that
  # call, and whether the call then fails depends on the operating system - this fails the same way
  # on every one.

  @doc """
  Connects as `:inet_tcp` does, then closes the socket and returns it.
  """
  @spec connect(:inet.socket_address(), :inet.port_number(), list, timeout) ::
          {:ok, :inet.socket()} | {:error, term}
  def connect(address, port, opts, timeout) do
    with {:ok, socket} <- :inet_tcp.connect(address, port, opts, timeout) do
      :ok = :gen_tcp.close(socket)

      {:ok, socket}
    end
  end

  @doc false
  @spec getaddrs(term, term) :: {:ok, [:inet.ip_address()]} | {:error, term}
  def getaddrs(address, timer), do: :inet_tcp.getaddrs(address, timer)

  @doc false
  @spec getserv(term) :: {:ok, :inet.port_number()} | {:error, term}
  def getserv(port), do: :inet_tcp.getserv(port)

  @doc """
  Returns the `:socket_options` that have a Postgrex connect go through this module, failing at
  the given step of `Postgrex.Protocol`: `:setopts` (the socket calls in its `connect/5`) or
  `:handshake` (the peer address lookup in its `handshake/3`, which a `:buffer` option given here
  makes Postgrex reach first).
  """
  @spec socket_options(:handshake | :setopts) :: keyword
  def socket_options(step \\ :setopts)

  def socket_options(:setopts), do: [tcp_module: __MODULE__]

  def socket_options(:handshake), do: [buffer: 65_536, tcp_module: __MODULE__]
end
