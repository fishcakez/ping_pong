defmodule PingPong.Client do

  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, nil, [name: __MODULE__])
  end

  def init(_) do
    children = [worker(PingPong.Client.Broker, []),
      supervisor(PingPong.Client.Pool, [])]
    supervise(children, [strategy: :rest_for_one])
  end
end
