defmodule PingPong.Client.Broker do

  @behaviour :sbroker

  def ask() do
    :sbroker.ask(__MODULE__)
  end

  def async_ask_r() do
    :sbroker.async_ask_r(__MODULE__, make_ref())
  end

  def cancel(ref) do
    :sbroker.cancel(__MODULE__, ref)
  end

  def start_link() do
    :sbroker.start_link({:local, __MODULE__}, __MODULE__, nil)
  end

  def init(_) do
    ask_spec = {:squeue_codel_timeout, {5, 100, 200}, :out, 4, :drop}
    ask_r_spec = {:squeue_naive, nil, :out, :infinity, :drop}
    interval = 200
    {:ok, {ask_spec, ask_r_spec, interval}}
  end
end
