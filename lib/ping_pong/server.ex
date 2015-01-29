defmodule PingPong.Server do

  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, nil, [name: __MODULE__])
  end

  def init(_) do
    {:ok, port} = Application.fetch_env(:ping_pong, :port)
    spec = :ranch.child_spec(__MODULE__, 1, :ranch_tcp, [port: port],
      PingPong.Server.Connection, [])
    supervise([spec], [strategy: :one_for_one])
  end
end
