defmodule PingPong.Server.Connection do

  require Logger

  @behaviour :ranch_protocol
  @behaviour :gen_fsm

  def start_link(ref, socket, transport, _) do
    {data, closed, error} = transport.messages()
    cb_info = {transport, data, closed, error}
    :gen_fsm.start_link(__MODULE__, {ref, cb_info, socket}, [])
  end

  ## init

  def init({ref, {transport, data, closed, error}, socket}) do
    :gen_fsm.send_event(self(), {:accept_ack, ref})
    {:ok, :init, %{transport: transport, data: data, closed: closed,
        error: error, socket: socket, buffer: <<>>}}
  end

  def init({:accept_ack, ref}, state) do
    :ok = :ranch.accept_ack(ref)
    active(state)
  end

  def init(event, _, state) do
    {:stop, {:bad_event, event}, state}
  end

  ## active

  def active(%{transport: transport, socket: socket} = state) do
    :ok = transport.setopts(socket, [packet: 4, active: :once])
    {:next_state, :active, state}
  end

  def active({:data, "ping"},
      %{transport: transport, socket: socket} = state) do
    transport.send(socket, "pong")
    active(state)
  end

  def active(:closed, state) do
    {:stop, :shutdown, state}
  end

  def active({:error, reason}, state) do
    {:stop, reason, state}
  end

  def active(event, _, state) do
    {:stop, {:bad_event, event}, state}
  end

  ## :gen_fsm api

  def handle_info({data, socket, binary}, state_name,
      %{data: data, socket: socket} = state) do
    apply(__MODULE__, state_name, [{:data, binary}, state])
  end
  def handle_info({closed, socket}, state_name,
      %{closed: closed, socket: socket} = state) do
    apply(__MODULE__, state_name, [:closed, state])
  end
  def handle_info({error, socket, reason}, state_name,
      %{error: error, socket: socket} = state) do
    apply(__MODULE__, state_name, [{:error, reason}, state])
  end

  def hande_info(msg, state_name, state) do
    :ok = Logger.info(fn() ->
      [inspect(self()), "got unknown message : "| inspect(msg)]
    end)
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

  def terminate(_, _, %{transport: transport, socket: socket}) do
    transport.close(socket)
  end

end
