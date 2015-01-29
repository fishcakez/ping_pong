defmodule PingPong do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(PingPong.Server, []),
      supervisor(PingPong.Client, [])
    ]

    opts = [strategy: :one_for_one, name: PingPong.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def ping() do
    case PingPong.Client.Broker.ask() do
      {:go, ref, pid, _} ->
        PingPong.Client.Connection.ping(pid, ref)
      {:drop, _} ->
        {:error, :dropped}
    end
  end

  def stop_server() do
    Supervisor.terminate_child(PingPong.Supervisor, PingPong.Server)
  end

  def start_server() do
    Supervisor.restart_child(PingPong.Supervisor, PingPong.Server)
  end
end
