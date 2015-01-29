defmodule PingPongTest do
  use ExUnit.Case

  test "ping" do
    :pong = PingPong.ping()
  end
end
