PingPong
========

```
mix deps.get
iex -S mix
iex(1)> PingPong.ping()
:pong
iex(2)> PingPong.stop_server()
:ok
iex(3)> PingPong.ping()
{:error, :dropped}
iex(4)> PingPong.start_server
{:ok, #PID<0.169.0>}
iex(5)> PingPong.ping
:pong
```

