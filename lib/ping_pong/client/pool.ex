defmodule PingPong.Client.Pool do

  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, nil, [name: __MODULE__])
  end

  def init(_) do
    children = for id <- 1..4 do
      worker(PingPong.Client.Connection, [],
        [id: {PingPong.Client.Connction, id}])
    end
    supervise(children, [strategy: :one_for_one])
  end
end
