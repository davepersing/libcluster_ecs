defmodule Cluster.Strategy.ECS do
  @moduledoc """
  Assumes you are using an ECS/Fargate cluster.  This strategy will
  periodically poll the AWS API and connect to all nodes it finds.

  ## Options

  * `cluster_arn` - ARN of the cluster running your tasks (required; e.g. "arn:aws:ecs:us-west-2:01234567890:cluster/my-cluster")
  * `task_arn` - ARN of the task definition running in your cluster (required; e.g. "arn:aws:ecs:us-west-2:01234567890:task/f1234567-1234-5678-1111-123456789012")
  * `node_sname` - The short name of the nodes you want to connect to (required; e.g. "my-app")
  * `poll_interval` - How often to poll in milliseconds (optional; default: 5_000)
  * `aws_region` - AWS Region to perform the request in (optional; default: us-east-1)

  ## Usage

      config :libcluster,
        topologies: [
          ecs_example: [
            strategy: #{__MODULE__},
            config: [
              poll_interval: 5_000,
              cluster_arn: "arn:aws:ecs:us-west-2:01234567890:cluster/my-cluster",
              task_arn: "arn:aws:ecs:us-west-2:01234567890:task/f1234567-1234-5678-1111-123456789012",
              node_sname: "my-app"
            ]
          ]
        ]
  """

  use GenServer
  use Cluster.Strategy
  import Cluster.Logger

  alias Cluster.Strategy.State
  alias ExAws.ECS

  @default_poll_interval 5_000
  @default_aws_region "us-east-1"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    state = %State{
      topology: Keyword.fetch!(opts, :topology),
      connect: Keyword.fetch!(opts, :connect),
      disconnect: Keyword.fetch!(opts, :disconnect),
      list_nodes: Keyword.fetch!(opts, :list_nodes),
      config: Keyword.get(opts, :config, [])
    }

    cluster_arn = Keyword.fetch!(state.config, :cluster_arn)
    task_arn = Keyword.fetch!(state.config, :task_arn)
    aws_region = Keyword.get(state.config, :aws_region, @default_aws_region)
    node_sname = Keyword.fetch!(state.config, :node_sname)
    poll_interval = Keyword.get(state.config, :poll_interval, @default_poll_interval)

    state = %{state | meta: {poll_interval, cluster_arn, task_arn, aws_region, node_sname}}

    info(state.topology, "starting ecs polling for #{cluster_arn} / #{task_arn}")

    {:ok, do_poll(state)}
  end

  def handle_info(:timeout, state), do: handle_info(:poll, state)
  def handle_info(:poll, state), do: {:noreply, do_poll(state)}
  def handle_info(_, state), do: {:noreply, state}

  defp do_poll(%State{meta: {poll_interval, cluster_arn, task_arn, aws_region, node_sname}} = state) do
    debug(state.topology, "Polling ECS cluster [#{cluster_arn}] for task: [#{task_arn}]...")

    me = node()

    nodes =
      cluster_arn
      |> ECS.describe_tasks(List.wrap(task_arn))
      |> ExAws.request!(region: aws_region)
      |> Map.get("tasks")
      |> Enum.filter(fn t -> t["taskArn"] == task_arn && t["healthStatus"] == "HEALTHY" end)
      |> Enum.map(fn t -> t["containers"] end)
      |> List.flatten()
      |> Enum.map(fn t -> t["networkInterfaces"] end)
      |> List.flatten()
      |> Enum.map(fn t -> t["privateIpv4Address"] end)
      |> Enum.map(&format_address(&1, node_sname))
      |> Enum.reject(fn n -> n == me end)

    debug(state.topology, "Found nodes: #{nodes}")

    Cluster.Strategy.connect_nodes(state.topology, state.connect, state.list_nodes, nodes)

    # reschedule a call to itself in poll_interval ms
    Process.send_after(self(), :poll, poll_interval)

    %{state | meta: {poll_interval, cluster_arn, task_arn, node_sname, nodes}}
  end

  defp format_address(ip_addr, node_sname) do
    "#{node_sname}@#{ip_addr}"
  end
end
