defmodule KafkaEx.Server do
  @moduledoc """
  Defines the KafkaEx.Server behavior that all Kafka API servers must implement, this module also provides some common callback functions that are injected into the servers that `use` it.
  """

  alias KafkaEx.NetworkClient
  alias KafkaEx.Protocol.ConsumerMetadata
  alias KafkaEx.Protocol.Heartbeat.Request, as: HeartbeatRequest
  alias KafkaEx.Protocol.JoinGroup.Request, as: JoinGroupRequest
  alias KafkaEx.Protocol.LeaveGroup.Request, as: LeaveGroupRequest
  alias KafkaEx.Protocol.Metadata
  alias KafkaEx.Protocol.Metadata.Broker
  alias KafkaEx.Protocol.Metadata.Response, as: MetadataResponse
  alias KafkaEx.Protocol.OffsetCommit.Request, as: OffsetCommitRequest
  alias KafkaEx.Protocol.OffsetFetch.Request, as: OffsetFetchRequest
  alias KafkaEx.Protocol.Fetch.Request, as: FetchRequest
  alias KafkaEx.Protocol.Produce
  alias KafkaEx.Protocol.Produce.Request, as: ProduceRequest
  alias KafkaEx.Protocol.SyncGroup.Request, as: SyncGroupRequest
  alias KafkaEx.Socket

  defmodule State do
    @moduledoc false

    alias KafkaEx.Protocol.Metadata.Response, as: MetadataResponse
    alias KafkaEx.Protocol.Metadata.Broker

    defstruct(
      metadata: %Metadata.Response{},
      brokers: [],
      event_pid: nil,
      consumer_metadata: %ConsumerMetadata.Response{},
      correlation_id: 0,
      consumer_group: nil,
      metadata_update_interval: nil,
      consumer_group_update_interval: nil,
      worker_name: KafkaEx.Server,
      ssl_options: [],
      use_ssl: false
    )

      @type t :: %State{
        metadata: Metadata.Response.t,
        brokers: [Broker.t],
        event_pid: nil | pid,
        consumer_metadata: ConsumerMetadata.Response.t,
        correlation_id: integer,
        metadata_update_interval: nil | integer,
        consumer_group_update_interval: nil | integer,
        worker_name: atom,
        ssl_options: KafkaEx.ssl_options,
        use_ssl: boolean
      }

    @spec increment_correlation_id(t) :: t
    def increment_correlation_id(state = %State{correlation_id: cid}) do
      %{state | correlation_id: cid + 1}
    end

    @spec broker_for_partition(t, binary, integer) :: Broker.t | nil
    def broker_for_partition(state, topic, partition) do
      MetadataResponse.broker_for_topic(
        state.metadata,
        state.brokers,
        topic,
        partition
      )
    end
  end

  @callback kafka_server_init(args :: [term]) ::
    {:ok, state} |
    {:ok, state, timeout | :hibernate} |
    :ignore |
    {:stop, reason :: any} when state: any
  @callback kafka_server_produce(request :: ProduceRequest.t, state :: State.t) ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term
  @callback kafka_server_consumer_group(state :: State.t) ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term
  @callback kafka_server_fetch(fetch_request :: FetchRequest.t, state :: State.t) ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term
  @callback kafka_server_offset(topic :: binary, parition :: integer, time :: :calendar.datetime | :latest | :earliest, state :: State.t) ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term
  @callback kafka_server_offset_fetch(request :: OffsetFetchRequest.t, state :: State.t) ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term
  @callback kafka_server_offset_commit(request :: OffsetCommitRequest.t, state :: State.t) ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term
  @callback kafka_server_consumer_group_metadata(state :: State.t) ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term
  @callback kafka_server_metadata(topic :: binary, state :: State.t) ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term
  @callback kafka_server_join_group(JoinGroupRequest.t, network_timeout :: integer, state :: State.t) ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term
  @callback kafka_server_sync_group(SyncGroupRequest.t, network_timeout :: integer, state :: State.t) ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term
  @callback kafka_server_leave_group(LeaveGroupRequest.t, network_timeout :: integer, state :: State.t) ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term
  @callback kafka_server_heartbeat(HeartbeatRequest.t, network_timeout :: integer, state :: State.t) ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term
  @callback kafka_server_update_metadata(state :: State.t) ::
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason :: term, new_state} when new_state: term
  @callback kafka_server_update_consumer_metadata(state :: State.t) ::
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason :: term, new_state} when new_state: term

  @default_call_timeout 5_000 # Default from GenServer

  @doc false
  @spec call(GenServer.server(), atom | tuple, nil | number | opts :: Keyword.t) :: term
  def call(server, request, opts \\ [])
  def call(server, request, opts) when is_list(opts) do
    call(server, request, opts[:timeout])
  end

  def call(server, request, nil) do
    # If using the configured sync_timeout that is less than the default
    # GenServer.call timeout, use the larger value unless explicitly set
    # using opts[:timeout].
    timeout = max(@default_call_timeout, Application.get_env(:kafka_ex, :sync_timeout, @default_call_timeout))
    call(server, request, timeout)
  end

  def call(server, request, timeout) when is_integer(timeout) do
    GenServer.call(server, request, timeout)
  end

  defmacro __using__(_) do
    # credo:disable-for-next-line Credo.Check.Refactor.LongQuoteBlocks
    quote location: :keep do
      @behaviour KafkaEx.Server
      require Logger
      alias KafkaEx.NetworkClient
      alias KafkaEx.Protocol.Offset

      @client_id "kafka_ex"
      @retry_count 3
      @wait_time 10
      @min_bytes 1
      @max_bytes 1_000_000
      @metadata_update_interval       30_000
      @sync_timeout                   1_000
      @ssl_options []

      def init([args]) do
        kafka_server_init([args])
      end

      def init([args, name]) do
        kafka_server_init([args, name])
      end

      def handle_call(:consumer_group, _from, state) do
        kafka_server_consumer_group(state)
      end

      def handle_call({:produce, produce_request}, _from, state) do
        kafka_server_produce(produce_request, state)
      end

      def handle_call({:fetch, fetch_request}, _from, state) do
        kafka_server_fetch(fetch_request, state)
      end

      def handle_call({:offset, topic, partition, time}, _from, state) do
        kafka_server_offset(topic, partition, time, state)
      end

      def handle_call({:offset_fetch, offset_fetch}, _from, state) do
        kafka_server_offset_fetch(offset_fetch, state)
      end

      def handle_call({:offset_commit, offset_commit_request}, _from, state) do
        kafka_server_offset_commit(offset_commit_request, state)
      end

      def handle_call({:consumer_group_metadata, _consumer_group}, _from, state) do
        kafka_server_consumer_group_metadata(state)
      end

      def handle_call({:metadata, topic}, _from, state) do
        kafka_server_metadata(topic, state)
      end

      def handle_call({:join_group, request, network_timeout}, _from, state) do
        kafka_server_join_group(request, network_timeout, state)
      end

      def handle_call({:sync_group, request, network_timeout}, _from, state) do
        kafka_server_sync_group(request, network_timeout, state)
      end

      def handle_call({:leave_group, request, network_timeout}, _from, state) do
        kafka_server_leave_group(request, network_timeout, state)
      end

      def handle_call({:heartbeat, request, network_timeout}, _from, state) do
        kafka_server_heartbeat(request, network_timeout, state)
      end

      def handle_info(:update_metadata, state) do
        kafka_server_update_metadata(state)
      end

      def handle_info(:update_consumer_metadata, state) do
        kafka_server_update_consumer_metadata(state)
      end

      def handle_info(_, state) do
        {:noreply, state}
      end

      def terminate(_, state) do
        Logger.log(:debug, "Shutting down worker #{inspect state.worker_name}")
        if state.event_pid do
          GenEvent.stop(state.event_pid)
        end
        Enum.each(state.brokers, fn(broker) -> NetworkClient.close_socket(broker.socket) end)
      end

      # KakfaEx.Server behavior default implementations
      def kafka_server_produce(produce_request, state) do
        correlation_id = state.correlation_id + 1
        produce_request_data = Produce.create_request(correlation_id, @client_id, produce_request)
        {broker, state, corr_id} = case MetadataResponse.broker_for_topic(state.metadata, state.brokers, produce_request.topic, produce_request.partition) do
          nil    ->
            {retrieved_corr_id, _} = retrieve_metadata(state.brokers, state.correlation_id, config_sync_timeout(), produce_request.topic)
            state = %{update_metadata(state) | correlation_id: retrieved_corr_id}
            {
              MetadataResponse.broker_for_topic(state.metadata, state.brokers, produce_request.topic, produce_request.partition),
              state,
              retrieved_corr_id
            }
          broker -> {broker, state, correlation_id}
        end

        response = case broker do
          nil    ->
            Logger.log(:error, "Leader for topic #{produce_request.topic} is not available (server)")
            :leader_not_available
          broker -> case produce_request.required_acks do
            0 ->  NetworkClient.send_async_request(broker, produce_request_data)
            _ ->
              response = broker
               |> NetworkClient.send_sync_request(produce_request_data, config_sync_timeout())
               |> Produce.parse_response
              # credo:disable-for-next-line Credo.Check.Refactor.Nesting
              case response do
                [%KafkaEx.Protocol.Produce.Response{partitions: [%{error_code: :no_error, offset: offset}], topic: topic}] when offset != nil ->
                  {:ok, offset}
                _ ->
                  {:error, response}
              end
          end
        end
        state = %{state | correlation_id: corr_id + 1}
        {:reply, response, state}
      end

      def kafka_server_offset(topic, partition, time, state) do
        offset_request = Offset.create_request(state.correlation_id, @client_id, topic, partition, time)
        {broker, state} = case MetadataResponse.broker_for_topic(state.metadata, state.brokers, topic, partition) do
          nil    ->
            state = update_metadata(state)
            {MetadataResponse.broker_for_topic(state.metadata, state.brokers, topic, partition), state}
          broker -> {broker, state}
        end

        {response, state} = case broker do
          nil ->
            Logger.log(:error, "Leader for topic #{topic} is not available")
            {:topic_not_found, state}
          _ ->
            response = broker
             |> NetworkClient.send_sync_request(offset_request, config_sync_timeout())
             |> Offset.parse_response
            state = %{state | correlation_id: state.correlation_id + 1}
            {response, state}
        end

        {:reply, response, state}
      end

      def kafka_server_metadata(topic, state) do
        {correlation_id, metadata} = retrieve_metadata(state.brokers, state.correlation_id, config_sync_timeout(), topic)
        updated_state = %{state | metadata: metadata, correlation_id: correlation_id}
        {:reply, metadata, updated_state}
      end

      def kafka_server_update_metadata(state) do
        {:noreply, update_metadata(state)}
      end

      def update_metadata(state) do
        {correlation_id, metadata} = retrieve_metadata(state.brokers, state.correlation_id, config_sync_timeout())
        metadata_brokers = metadata.brokers
        brokers = state.brokers
          |> remove_stale_brokers(metadata_brokers)
          |> add_new_brokers(metadata_brokers, state.ssl_options, state.use_ssl)
        %{state | metadata: metadata, brokers: brokers, correlation_id: correlation_id + 1}
      end

      # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
      def retrieve_metadata(brokers, correlation_id, sync_timeout, topic \\ []), do: retrieve_metadata(brokers, correlation_id, sync_timeout, topic, @retry_count, 0)
      # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
      def retrieve_metadata(_, correlation_id, _sync_timeout, topic, 0, error_code) do
        Logger.log(:error, "Metadata request for topic #{inspect topic} failed with error_code #{inspect error_code}")
        {correlation_id, %Metadata.Response{}}
      end
      # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
      def retrieve_metadata(brokers, correlation_id, sync_timeout, topic, retry, _error_code) do
        metadata_request = Metadata.create_request(correlation_id, @client_id, topic)
        data = first_broker_response(metadata_request, brokers, sync_timeout)
        response = case data do
                     nil ->
                       Logger.log(:error, "Unable to fetch metadata from any brokers.  Timeout is #{sync_timeout}.")
                       raise "Unable to fetch metadata from any brokers.  Timeout is #{sync_timeout}."
                       :no_metadata_available
                     data ->
                       Metadata.parse_response(data)
                   end

                   case Enum.find(response.topic_metadatas, &(&1.error_code == :leader_not_available)) do
          nil  -> {correlation_id + 1, response}
          topic_metadata ->
            :timer.sleep(300)
            retrieve_metadata(brokers, correlation_id + 1, sync_timeout, topic, retry - 1, topic_metadata.error_code)
        end
      end

      defoverridable [
        kafka_server_produce: 2, kafka_server_offset: 4,
        kafka_server_metadata: 2, kafka_server_update_metadata: 1,
      ]

      defp kafka_common_init(args, name) do
        use_ssl = Keyword.get(args, :use_ssl, false)
        ssl_options = Keyword.get(args, :ssl_options, [])

        uris = Keyword.get(args, :uris, [])
        metadata_update_interval = Keyword.get(
          args,
          :metadata_update_interval,
          @metadata_update_interval
        )

        brokers = for {host, port} <- uris do
          connect_broker(host, port, ssl_options, use_ssl)
        end

        {correlation_id, metadata} = retrieve_metadata(
          brokers,
          0,
          config_sync_timeout()
        )

        state = %State{
          metadata: metadata,
          brokers: brokers,
          correlation_id: correlation_id,
          metadata_update_interval: metadata_update_interval,
          ssl_options: ssl_options,
          use_ssl: use_ssl,
          worker_name: name
        }

        state = update_metadata(state)
        {:ok, _} = :timer.send_interval(
          state.metadata_update_interval,
          :update_metadata
        )

        state
      end

      defp connect_broker(host, port, ssl_opts, use_ssl) do
        %Broker{
          host: host,
          port: port,
          socket: NetworkClient.create_socket(host, port, ssl_opts, use_ssl)
        }
      end

      defp client_request(request, state) do
        %{
          request |
          client_id: @client_id,
          correlation_id: state.correlation_id
        }
      end

      # gets the broker for a given partition, updating metadata if necessary
      # returns {broker, maybe_updated_state}
      defp broker_for_partition_with_update(state, topic, partition) do
        case State.broker_for_partition(state, topic, partition) do
          nil ->
            updated_state = update_metadata(state)
            {
              State.broker_for_partition(updated_state, topic, partition),
              updated_state
            }
          broker ->
            {broker, state}
        end
      end

      # assumes module.create_request(request) and module.parse_response
      # both work
      defp network_request(request, module, state) do
        {broker, updated_state} = broker_for_partition_with_update(
          state,
          request.topic,
          request.partition
        )

        case broker do
          nil ->
            Logger.error(fn ->
              "Leader for topic #{request.topic} is not available (Server network_request)"
            end)
            {{:error, :topic_not_found}, updated_state}
          _ ->
            wire_request = request
            |> client_request(updated_state)
            |> module.create_request

            response = broker
            |> NetworkClient.send_sync_request(
              wire_request,
              config_sync_timeout()
            )
            |> module.parse_response

            state_out = State.increment_correlation_id(updated_state)

            {response, state_out}
        end
      end

      defp remove_stale_brokers(brokers, metadata_brokers) do
        {brokers_to_keep, brokers_to_remove} = Enum.partition(brokers, fn(broker) ->
          Enum.find_value(metadata_brokers, &(broker.node_id == -1 || (broker.node_id == &1.node_id) && broker.socket && Socket.info(broker.socket)))
        end)
        case length(brokers_to_keep) do
          0 -> brokers_to_remove
          _ -> Enum.each(brokers_to_remove, fn(broker) ->
            Logger.log(:debug, "Closing connection to broker #{broker.node_id}: #{inspect broker.host} on port #{inspect broker.port}")
            NetworkClient.close_socket(broker.socket)
          end)
            brokers_to_keep
        end
      end

      defp add_new_brokers(brokers, [], _, _), do: brokers
      defp add_new_brokers(brokers, [metadata_broker|metadata_brokers], ssl_options, use_ssl) do
        case Enum.find(brokers, &(metadata_broker.node_id == &1.node_id)) do
          nil -> Logger.log(:debug, "Establishing connection to broker #{metadata_broker.node_id}: #{inspect metadata_broker.host} on port #{inspect metadata_broker.port}")
            add_new_brokers([%{metadata_broker | socket: NetworkClient.create_socket(metadata_broker.host, metadata_broker.port, ssl_options, use_ssl)} | brokers], metadata_brokers, ssl_options, use_ssl)
          _ -> add_new_brokers(brokers, metadata_brokers, ssl_options, use_ssl)
        end
      end

      defp first_broker_response(request, brokers, sync_timeout) do
        Enum.find_value(brokers, fn(broker) ->
          if Broker.connected?(broker) do
            NetworkClient.send_sync_request(broker, request, sync_timeout)
          end
        end)
      end

      defp config_sync_timeout(timeout \\ nil) do
        timeout || Application.get_env(:kafka_ex, :sync_timeout, @sync_timeout)
      end
    end
  end
end
