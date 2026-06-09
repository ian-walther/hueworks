defmodule Hueworks.HomeKit.HAP do
  @moduledoc false

  use Supervisor

  @default_port 51_827
  @default_mdns_host "hueworks"
  @default_bind_ip {0, 0, 0, 0}

  def start_link(%HAP.AccessoryServer{} = accessory_server) do
    Supervisor.start_link(__MODULE__, accessory_server)
  end

  @impl true
  def init(%HAP.AccessoryServer{} = accessory_server) do
    configure_mdns_hosts()

    accessory_server
    |> HAP.AccessoryServer.compile()
    |> child_specs()
    |> Supervisor.init(strategy: :rest_for_one)
  end

  def child_specs(%HAP.AccessoryServer{} = accessory_server) do
    [
      {HAP.PersistentStorage, accessory_server.data_path},
      {HAP.AccessoryServerManager, accessory_server},
      HAP.EventManager,
      HAP.PairSetup,
      {Bandit,
       plug: HAP.HTTPServer,
       ip: bind_ip(),
       port: port(),
       http_1_options: [clear_process_dict: false],
       thousand_island_options: [
         handler_module: Hueworks.HomeKit.HAPSessionHandler,
         transport_module: Hueworks.HomeKit.HAPSessionTransport
       ]}
    ]
  end

  def port do
    Application.get_env(:hueworks, :homekit_port, @default_port)
  end

  def mdns_host do
    Application.get_env(:hueworks, :homekit_mdns_host, @default_mdns_host)
  end

  defp bind_ip do
    Application.get_env(:hueworks, :homekit_bind_ip, @default_bind_ip)
  end

  defp configure_mdns_hosts do
    case mdns_host() do
      host when is_binary(host) and host != "" -> MdnsLite.set_hosts([host])
      _ -> :ok
    end
  end
end
