defmodule Cluster.Strategy.ECSTest do
  use ExUnit.Case
  doctest Cluster.Strategy.ECS

  test "greets the world" do
    assert Cluster.Strategy.ECS.hello() == :world
  end
end
