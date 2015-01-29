defmodule PingPong.Client.Connection do

  @behaviour :gen_fsm

  def ping(pid, ref) do
    :gen_fsm.sync_send_event(pid, {:ping, ref}, 5000)
  end

  def start_link() do
    :gen_fsm.start_link(__MODULE__, nil, [])
  end

  def init(_) do
    state = %{socket: nil, async: nil, ref: nil, client: nil, monitor: nil,
      from: nil}
    {:ok, :connect, state, 0}
  end

  ## connect - connecting (with retries) to server

  defp connect(state) do
    {:next_state, :connect, state, 0}
  end

  def connect(:timeout, state) do
    {:ok, port} = Application.fetch_env(:ping_pong, :port)
    opts = [packet: 4, active: :once, mode: :binary]
    case :gen_tcp.connect({127,0,0,1}, port, opts, 3000) do
      {:ok, socket} ->
        ready(%{state | socket: socket})
      {:error, _} ->
        {:next_state, :connect, state, 3000}
    end
  end

  def connect({:ping, ref}, from, state) when is_reference(ref) do
    :gen_fsm.reply(from, {:error, :bad_reference})
    connect(state)
  end

  ## ready - awaiting client ref/pid

  defp ready(state) do
    {:await, async, _} = PingPong.Client.Broker.async_ask_r()
    {:next_state, :ready, %{state | async: async}}
  end

  def ready({:ping, ref}, _, state) when is_reference(ref) do
    {:reply, {:error, :bad_reference}, :ready, state}
  end

  ## ready_closed - lost tcp connection, awaiting client ref/pid

  defp ready_closed(%{socket: socket} = state) do
    :gen_tcp.close(socket)
    {:next_state, :ready_closed, %{state | socket: nil}}
  end

  def ready_closed(event, state) do
    {:stop, {:bad_event, event}, state}
  end

  def ready_closed({:ping, ref}, _, state) when is_reference(ref) do
    {:reply, {:error, :bad_reference}, :ready_closed, state}
  end

  ## await - received client ref/pid, awaiting client call

  defp await(%{client: client} = state) do
    monitor = Process.monitor(client)
    {:next_state, :await, %{state | monitor: monitor}}
  end

  def await(event, state) do
    {:stop, {:bad_event, event}, state}
  end

  def await({:ping, ref}, from, %{ref: ref, socket: socket} = state) do
    :gen_tcp.send(socket, "ping")
    recv(%{state | ref: nil, from: from})
  end
  def await({:ping, ref}, _, state) when is_reference(ref) do
    {:reply, {:error, :bad_reference}, :await, state}
  end

  ## await_closed - lost tcp connection, awaiting client call

  defp await_closed(%{monitor: nil, socket: nil, client: client} = state) do
    monitor = Process.monitor(client)
    {:next_state, :ready_closed, %{state | monitor: monitor}}
  end
  defp await_closed(%{socket: socket} = state) do
    :gen_tcp.close(socket)
    {:next_state, :await_closed, %{state | socket: nil}}
  end

  def await_closed(event, state) do
    {:stop, {:bad_event, event}, state}
  end

  def await_closed({:ping, ref}, from, %{ref: ref} = state) do
    closed_restart(%{state | ref: nil, from: from})
  end
  def await_closed({:ping, ref}, _, state) when is_reference(ref) do
    {:reply, {:error, :bad_reference}, :await_closed, state}
  end

  ## recv - received client call, waiting for tcp data

  defp recv(state) do
    {:next_state, :recv, state, 3000}
  end

  def recv(:timeout, state) do
    recv_restart(state)
  end

  def recv({:ping, ref}, _, state) when is_reference(ref) do
    {:reply, {:error, :bad_reference}, :recv, state, 3000}
  end

  ## gen_fsm api

  def handle_info(_, :connect, state) do
    connect(state)
  end
  def handle_info({async, {:go, ref, client, _}}, :ready,
      %{async: async} = state) do
    await(%{state | ref: ref, client: client, async: nil})
  end
  def handle_info({async, {:go, ref, client, _}}, :ready_closed,
      %{async: async} = state) do
    await_closed(%{state | ref: ref, client: client})
  end
  def handle_info({async, {:drop, _}}, :ready, %{async: async} = state) do
    {:stop, {:shutdown, :dropped}, %{state | async: nil}}
  end
  def handle_info({async, {:drop, _}}, :ready_closed, %{async: async} = state) do
    {:stop, {:shutdown, :dropped}, %{state | async: nil}}
  end
  def handle_info({:DOWN, monitor, _, _, _}, :await,
      %{monitor: monitor} = state) do
    ready(%{state | monitor: nil})
  end
  def handle_info({:DOWN, monitor, _, _, _}, :await_closed,
      %{monitor: monitor} = state) do
    closed_restart(%{state | monitor: nil})
  end
  def handle_info({:DOWN, monitor, _, _, _}, :recv,
      %{monitor: monitor} = state) do
    recv_restart(%{state | monitor: nil})
  end
  def handle_info({:tcp, socket, "pong"}, :recv,
      %{socket: socket, from: from, monitor: monitor} = state) do
    :gen_fsm.reply(from, :pong)
    Process.demonitor(monitor, [:flush])
    :ok = :inet.setopts(socket, [active: :once])
    ready(%{state | monitor: nil, ref: nil, from: nil})
  end
  def handle_info({:tcp, socket, data}, _, %{socket: socket} = state) do
    {:stop, {:bad_data, data}, state}
  end
  def handle_info({:tcp_closed, socket}, :ready, %{socket: socket} = state) do
    ready_restart(state)
  end
  def handle_info({:tcp_closed, socket}, :await, %{socket: socket} = state) do
    await_closed(state)
  end
  def handle_info({:tcp_closed, socket}, :recv, %{socket: socket} = state) do
    recv_restart(state)
  end
  def handle_info({:tcp_error, socket, _}, :ready, %{socket: socket} = state) do
    ready_restart(state)
  end
  def handle_info({:tcp_error, socket, _}, :await, %{socket: socket} = state) do
    await_closed(state)
  end
  def handle_info({:tcp_error, socket}, :recv, %{socket: socket} = state) do
    recv_restart(state)
  end
  def handle_info(_, :recv, state) do
    recv(state)
  end
  def handle_info(_, state_name, state) do
    {:next_state, state_name, state}
  end

  def handle_event(event, _, state) do
    {:stop, {:bad_event, event}, state}
  end

  def handle_sync_event(event, _, _, state) do
    {:stop, {:bad_event, event}, state}
  end

  def code_change(_, state_name, state, _) do
    {:ok, state_name, state}
  end

  def terminate(_, _, _) do
    :ok
  end

  ## Helpers

  defp ready_restart(%{async: async} = state) do
    case PingPong.Client.Broker.cancel(async) do
      :ok ->
        restart(%{state | async: nil})
      {:error, :not_found} ->
        ready_closed(state)
    end
  end

  defp recv_restart(%{monitor: monitor, from: from} = state) do
    if is_reference(monitor), do: Process.demonitor(monitor, [:flush])
    :gen_fsm.reply(from, :pang)
    restart(%{state | monitor: nil, client: nil, from: nil})
  end

  defp closed_restart(%{monitor: monitor, from: from} = state) do
    if is_reference(monitor), do: Process.demonitor(monitor, [:flush])
    :gen_fsm.reply(from, :pang)
    connect(%{state | monitor: nil, client: nil, from: nil})
  end

  defp restart(%{socket: socket} = state) do
    :gen_tcp.close(socket)
    connect(%{state | socket: nil})
  end
end
